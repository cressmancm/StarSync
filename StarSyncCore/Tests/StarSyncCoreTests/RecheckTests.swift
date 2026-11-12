import Foundation
import Testing
@testable import StarSyncCore

/// A plan is built from a snapshot of Photos, and Photos keeps changing after
/// that. These cover what happens when the rating a row was planned against is
/// no longer the rating Photos holds.
@Suite("Recheck against live ratings")
struct RecheckTests {

    func planned(lr: Int, photos: Int) -> PlannedChange {
        SyncPlanner.decide(
            asset: LRAsset(id: "a", fileName: "DSC_0001.NEF", rating: lr),
            photo: PhotoAsset(id: "p", originalFilename: "DSC_0001.jpg",
                              creationDate: nil, rating: photos, isEditable: true)
        )
    }

    // MARK: Nothing has moved

    @Test("Photos still holds what the preview showed, so the row is written")
    func untouched() {
        let change = planned(lr: 4, photos: 0)
        #expect(SyncPlanner.recheck(change, liveRating: 0) == .write(4))
    }

    @Test("A row with nothing to write stays that way")
    func nothingPlanned() {
        let change = planned(lr: 5, photos: 3)
        #expect(change.newRating == nil)
        #expect(SyncPlanner.recheck(change, liveRating: 1) == .alreadyCorrect)
    }

    @Test("Someone else already set the intended rating")
    func alreadyThere() {
        let change = planned(lr: 4, photos: 0)
        #expect(SyncPlanner.recheck(change, liveRating: 4) == .alreadyCorrect)
    }

    // MARK: Photos moved underneath the preview

    @Test("A rating added after the preview is not overwritten")
    func respectsANewRating() {
        // Planned as a blank to fill. By write time it is not blank any more,
        // and filling blanks is the only thing done without being asked.
        let change = planned(lr: 4, photos: 0)
        #expect(change.willWrite)
        #expect(SyncPlanner.recheck(change, liveRating: 3) == .changedInPhotos(liveRating: 3))
    }

    @Test("An explicit choice is honoured even though Photos moved")
    func overrideStands() {
        var plan = SyncPlan(
            changes: [planned(lr: 4, photos: 0)],
            unmatchedCount: 0,
            ambiguous: []
        )
        plan.setRating(5, for: "a")
        let change = plan.changes[0]
        #expect(change.isManualOverride)
        #expect(SyncPlanner.recheck(change, liveRating: 3) == .write(5))
    }

    // MARK: Where the override flag comes from

    @Test("The planner does not mark its own decisions as the person's")
    func plannerDecisionsAreNotOverrides() {
        #expect(!planned(lr: 4, photos: 0).isManualOverride)
        #expect(!planned(lr: 4, photos: 2).isManualOverride)
    }

    @Test("Resolving the review list in bulk counts as the person deciding")
    func bulkResolutionIsAnOverride() {
        var plan = SyncPlan(
            changes: [planned(lr: 5, photos: 2)],
            unmatchedCount: 0,
            ambiguous: []
        )
        #expect(plan.changes[0].needsReview)
        plan.resolveAllRemainingFromLightroom()
        #expect(plan.changes[0].isManualOverride)
        #expect(plan.manualOverrides.count == 1)
        // And it survives Photos moving, because it was asked for.
        #expect(SyncPlanner.recheck(plan.changes[0], liveRating: 1)
                == .write(5))
    }

    @Test("Keeping Photos' rating in bulk writes nothing")
    func keepingFromPhotosWritesNothing() {
        var plan = SyncPlan(
            changes: [planned(lr: 5, photos: 2)],
            unmatchedCount: 0,
            ambiguous: []
        )
        plan.keepAllRemainingFromPhotos()
        #expect(plan.writes.isEmpty)
    }
}

@Suite("Refreshing a report's ratings")
struct ReportRefreshTests {

    func report(photoRating: Int) -> MatchReport {
        MatchReport(
            matches: [
                Match(
                    asset: LRAsset(id: "a", fileName: "DSC_0001.NEF", rating: 5),
                    outcome: .matched(
                        PhotoAsset(id: "p", originalFilename: "DSC_0001.jpg",
                                   creationDate: nil, rating: photoRating, isEditable: true),
                        confidence: .uniqueFilename
                    )
                ),
                Match(
                    asset: LRAsset(id: "b", fileName: "DSC_0002.NEF", rating: 3),
                    outcome: .notInPhotos
                ),
            ],
            unidentifiablePhotos: 0
        )
    }

    @Test("A fresh rating replaces the one the snapshot held")
    func ratingIsReplaced() throws {
        let refreshed = report(photoRating: 0).updatingPhotoRatings(["p": 3])
        #expect(try #require(refreshed.matches[0].photo).rating == 3)
    }

    @Test("Matching is not disturbed: the pairing and its confidence survive")
    func pairingSurvives() throws {
        let refreshed = report(photoRating: 0).updatingPhotoRatings(["p": 3])
        #expect(refreshed.matches.count == 2)
        #expect(refreshed.matches[0].asset.id == "a")
        #expect(refreshed.matches[1].outcome == .notInPhotos)
        if case .matched(_, let confidence) = refreshed.matches[0].outcome {
            #expect(confidence == .uniqueFilename)
        } else {
            Issue.record("the match was lost")
        }
    }

    @Test("Photos not mentioned are left exactly as they were")
    func othersUntouched() throws {
        let refreshed = report(photoRating: 2).updatingPhotoRatings(["somebody-else": 5])
        #expect(try #require(refreshed.matches[0].photo).rating == 2)
    }

    @Test("Only matched photos are worth re-reading")
    func identifiersAreOnlyTheMatches() {
        #expect(report(photoRating: 0).matchedPhotoIdentifiers == ["p"])
    }

    @Test("A refreshed report plans against the new rating, not the old one")
    func planUsesTheFreshRating() {
        // The snapshot said unrated, so Add only intended to write. Photos has
        // since been rated 3, so there is nothing for Add only to do.
        let stale = report(photoRating: 0)
        #expect(SyncPlanner.plan(from: stale).writes.count == 1)

        let fresh = stale.updatingPhotoRatings(["p": 3])
        let plan = SyncPlanner.plan(from: fresh)
        #expect(plan.writes.isEmpty)
        #expect(plan.conflicts.count == 1)
    }
}
