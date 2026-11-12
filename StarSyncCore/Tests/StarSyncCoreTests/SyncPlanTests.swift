import Foundation
import Testing
@testable import StarSyncCore

@Suite("SyncPlan")
struct SyncPlanTests {

    func decide(lr: Int, photos: Int, editable: Bool = true) -> PlannedChange {
        SyncPlanner.decide(
            asset: LRAsset(id: "a", fileName: "DSC_0001.NEF", rating: lr),
            photo: PhotoAsset(id: "p", originalFilename: "DSC_0001.jpg",
                              creationDate: nil, rating: photos, isEditable: editable)
        )
    }

    // MARK: The truth table

    @Test("Photos unrated: the Lightroom rating is written")
    func unratedInPhotos() {
        let change = decide(lr: 4, photos: 0)
        #expect(change.reason == .newRating)
        #expect(change.newRating == 4)
        #expect(change.willWrite)
        #expect(!change.needsReview)
    }

    @Test("a differing rating is deferred to the person")
    func reviewConflict() {
        let change = decide(lr: 5, photos: 4)
        #expect(change.reason == .conflict)
        #expect(change.newRating == nil)
        #expect(change.needsReview)
        #expect(!change.willWrite)
    }

    @Test("ratings that already agree are left alone")
    func alreadyMatches() {
        let change = decide(lr: 3, photos: 3)
        #expect(change.reason == .alreadyMatches)
        #expect(change.newRating == nil)
        #expect(!change.willWrite)
    }

    // MARK: The rule that protects existing ratings

    @Test("an unrated Lightroom photo never clears a Photos rating")
    func zeroStarsNeverClears() {
        let change = decide(lr: 0, photos: 3)
        #expect(change.reason == .notRatedInLightroom)
        #expect(change.newRating == nil)
        #expect(!change.willWrite)
        #expect(!change.needsReview)
    }

    @Test("unrated on both sides is a no-op")
    func zeroOnBothSides() {
        let change = decide(lr: 0, photos: 0)
        #expect(change.newRating == nil)
        #expect(!change.willWrite)
    }

    // MARK: Read-only assets

    @Test("a photo Photos will not let us edit is reported, not queued")
    func notEditable() {
        let change = decide(lr: 5, photos: 0, editable: false)
        #expect(change.reason == .notEditable)
        #expect(!change.willWrite)
    }

    @Test("an agreeing read-only photo is simply already correct")
    func notEditableButAlreadyCorrect() {
        let change = decide(lr: 3, photos: 3, editable: false)
        #expect(change.reason == .alreadyMatches)
        #expect(!change.willWrite)
    }

    // MARK: Plans

    func report(_ pairs: [(lr: Int, photos: Int)]) -> MatchReport {
        let matches = pairs.enumerated().map { index, pair in
            Match(
                asset: LRAsset(id: "a\(index)", fileName: "DSC_\(index).NEF", rating: pair.lr),
                outcome: .matched(
                    PhotoAsset(id: "p\(index)", originalFilename: "DSC_\(index).jpg",
                               creationDate: nil, rating: pair.photos),
                    confidence: .uniqueFilename
                )
            )
        }
        return MatchReport(matches: matches, unidentifiablePhotos: 0)
    }

    @Test("a plan counts writes and conflicts")
    func planCounts() {
        let plan = SyncPlanner.plan(
            from: report([(5, 0), (4, 0), (5, 3), (2, 2), (0, 4)])
        )
        #expect(plan.writes.count == 2)       // the two unrated in Photos
        #expect(plan.conflicts.count == 1)    // 5 vs 3
        #expect(plan.changes.count == 5)
    }

    @Test("mismatches are held back until they are resolved")
    func planReview() {
        var plan = SyncPlanner.plan(from: report([(5, 0), (5, 3), (4, 2)]))
        #expect(plan.writes.count == 1)
        #expect(plan.pendingReview.count == 2)

        plan.resolveAllRemainingFromLightroom()
        #expect(plan.pendingReview.isEmpty)
        #expect(plan.writes.count == 3)
    }

    @Test("keeping Photos' side resolves a review without writing")
    func keepPhotos() {
        var plan = SyncPlanner.plan(from: report([(5, 3)]))
        plan.keepAllRemainingFromPhotos()
        #expect(plan.pendingReview.isEmpty)
        #expect(plan.writes.isEmpty)
    }

    @Test("a single row can be overridden by hand")
    func perRowOverride() {
        var plan = SyncPlanner.plan(from: report([(5, 3)]))
        #expect(plan.writes.isEmpty)

        let id = plan.changes[0].id
        plan.setRating(5, for: id)
        #expect(plan.writes.count == 1)

        plan.setRating(nil, for: id)
        #expect(plan.writes.isEmpty)

        // An override to what Photos already has is not a write.
        plan.setRating(3, for: id)
        #expect(plan.writes.isEmpty)
    }

    @Test("overriding an unknown row changes nothing")
    func overrideUnknownRow() {
        var plan = SyncPlanner.plan(from: report([(5, 3)]))
        plan.setRating(5, for: "not-a-real-id")
        #expect(plan.writes.isEmpty)
    }

    @Test("unmatched and ambiguous photos are carried into the plan")
    func planCarriesUnmatched() {
        let matched = Match(
            asset: LRAsset(id: "a", fileName: "a.NEF", rating: 5),
            outcome: .matched(PhotoAsset(id: "p", originalFilename: "a.jpg",
                                         creationDate: nil, rating: 0),
                              confidence: .uniqueFilename)
        )
        let missing = Match(asset: LRAsset(id: "b", fileName: "b.NEF", rating: 5),
                            outcome: .notInPhotos)
        let unsure = Match(
            asset: LRAsset(id: "c", fileName: "c.NEF", rating: 5),
            outcome: .ambiguous([
                PhotoAsset(id: "p1", originalFilename: "c.jpg", creationDate: nil, rating: 0),
                PhotoAsset(id: "p2", originalFilename: "c.jpg", creationDate: nil, rating: 0),
            ])
        )
        let plan = SyncPlanner.plan(
            from: MatchReport(matches: [matched, missing, unsure], unidentifiablePhotos: 0)
        )
        #expect(plan.changes.count == 1)
        #expect(plan.unmatchedCount == 1)
        #expect(plan.ambiguous.count == 1)
        #expect(plan.summary.contains("1 to write"))
        #expect(plan.summary.contains("1 ambiguous"))
    }

    // MARK: Folding a written rating back into the snapshot

    @Test("withRating changes only the rating")
    func withRating() {
        let before = PhotoAsset(
            id: "p1", originalFilename: "DSC_0001.jpg",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            rating: 0, pixelWidth: 6240, pixelHeight: 4160, isEditable: true
        )
        let after = before.withRating(5)

        #expect(after.rating == 5)
        #expect(after.id == before.id)
        #expect(after.originalFilename == before.originalFilename)
        #expect(after.creationDate == before.creationDate)
        #expect(after.pixelWidth == before.pixelWidth)
        #expect(after.pixelHeight == before.pixelHeight)
        #expect(after.isEditable == before.isEditable)
        // The original is untouched.
        #expect(before.rating == 0)
    }

    @Test("a photo updated after a write no longer conflicts")
    func writtenPhotoStopsConflicting() {
        let asset = LRAsset(id: "a", fileName: "DSC_0001.NEF", rating: 5)
        let before = PhotoAsset(id: "p", originalFilename: "DSC_0001.jpg",
                                creationDate: nil, rating: 0)

        let first = SyncPlanner.decide(asset: asset, photo: before)
        #expect(first.willWrite)

        // After the write lands, planning again should find nothing to do —
        // this is what folding the new rating back into the snapshot buys.
        let second = SyncPlanner.decide(asset: asset, photo: before.withRating(5))
        #expect(second.reason == .alreadyMatches)
        #expect(!second.willWrite)
    }

    @Test("changes come back sorted by the name shown on screen")
    func changesAreSorted() {
        // The review list leans on this: it filters `changes` into sections
        // and never sorts, so the order has to be right here.
        let names = ["DSC_30.jpg", "DSC_4.jpg", "DSC_200.jpg", "DSC_1.jpg"]
        let matches = names.enumerated().map { index, name in
            Match(
                asset: LRAsset(id: "a\(index)", fileName: name, rating: 5),
                outcome: .matched(
                    PhotoAsset(id: "p\(index)", originalFilename: name,
                               creationDate: nil, rating: 0),
                    confidence: .uniqueFilename
                )
            )
        }
        let plan = SyncPlanner.plan(from: MatchReport(matches: matches, unidentifiablePhotos: 0))
        // Numeric-aware, so 4 sorts before 30 rather than after.
        #expect(plan.changes.map(\.displayName) == ["DSC_1.jpg", "DSC_4.jpg", "DSC_30.jpg", "DSC_200.jpg"])
    }

    @Test("every rating 1-5 round-trips through a plan", arguments: 1...5)
    func allRatings(stars: Int) {
        let plan = SyncPlanner.plan(from: report([(stars, 0)]))
        #expect(plan.writes.count == 1)
        #expect(plan.writes[0].newRating == stars)
    }
}
