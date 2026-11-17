import Foundation

/// Why a photo is being written, skipped, or held for review.
public enum ChangeReason: String, Sendable, Equatable {
    /// Photos has no rating; Lightroom has one.
    case newRating
    /// Both have a rating and they differ.
    case conflict
    /// Both agree already.
    case alreadyMatches
    /// Lightroom is at 0★ — not triaged, so nothing to contribute.
    case notRatedInLightroom
    /// Photos will not let this asset's properties change.
    case notEditable
}

/// What will happen to one photo.
public struct PlannedChange: Sendable, Identifiable, Equatable {
    public let asset: LRAsset
    public let photo: PhotoAsset
    public let reason: ChangeReason
    /// The rating to write, or nil to leave the photo as it is.
    public var newRating: Int?
    /// True when planning deferred this to the person rather than deciding.
    public let needsReview: Bool
    /// True when the person set this rating themselves rather than planning
    /// deciding it.
    ///
    /// It matters at write time. If Photos changed underneath the preview, a
    /// rating that was inferred is dropped, but one the person chose is still
    /// written: they said what they wanted, and silently discarding that would
    /// be worse than acting on a stale comparison.
    public var isManualOverride: Bool

    public var id: String { asset.id }
    public var lightroomRating: Int { asset.rating }
    public var photosRating: Int { photo.rating }

    /// What to call this photo on screen. Photos' own filename where it has
    /// one, since that is what the person sees in Photos.app.
    public var displayName: String { photo.originalFilename ?? asset.fileName }

    /// Whether this row will write when the plan is applied.
    public var willWrite: Bool {
        guard let newRating else { return false }
        return newRating != photo.rating && photo.isEditable
    }

    public init(
        asset: LRAsset,
        photo: PhotoAsset,
        reason: ChangeReason,
        newRating: Int?,
        needsReview: Bool,
        isManualOverride: Bool = false
    ) {
        self.asset = asset
        self.photo = photo
        self.reason = reason
        self.newRating = newRating
        self.needsReview = needsReview
        self.isManualOverride = isManualOverride
    }
}

/// Everything a run intends to do, ready to show before anything is written.
public struct SyncPlan: Sendable {
    /// Every matched photo, in the order they are shown: by display name.
    public var changes: [PlannedChange]
    /// Lightroom photos with no counterpart in Photos.
    public let unmatchedCount: Int
    /// Rated Lightroom photos whose counterpart could not be identified
    /// uniquely.
    ///
    /// Only rated ones. An unrated photo is never written whatever it matches,
    /// so not knowing which photo it is has no consequence worth reporting —
    /// and a catalog full of untriaged raws would otherwise bury the handful
    /// of cases where the ambiguity actually stops a rating getting through.
    public let ambiguous: [Match]

    public init(changes: [PlannedChange], unmatchedCount: Int, ambiguous: [Match]) {
        self.changes = changes
        self.unmatchedCount = unmatchedCount
        self.ambiguous = ambiguous
    }

    public var writes: [PlannedChange] { changes.filter(\.willWrite) }
    public var conflicts: [PlannedChange] { changes.filter { $0.reason == .conflict } }
    public var pendingReview: [PlannedChange] { changes.filter { $0.needsReview && $0.newRating == nil } }
    public var notEditable: [PlannedChange] { changes.filter { $0.reason == .notEditable } }

    public var summary: String {
        // Grouped digits, like every other count the app shows: a catalog
        // puts four figures in here routinely, and "3413" read as a number
        // nowhere else in the window does.
        var parts = ["\(writes.count.formatted()) to write"]
        // The ones still waiting, not every row that ever disagreed. `reason`
        // records why a row was flagged and never changes when it is settled,
        // so counting that left the headline claiming four conflicts directly
        // under a list where all four had just been resolved.
        let undecided = pendingReview.count
        if undecided > 0 {
            // The one case that reads as a mistake if it is left plural: a
            // single disagreement is the most common thing this line reports.
            let word = undecided == 1 ? "conflict" : "conflicts"
            parts.append("\(undecided.formatted()) \(word)")
        }
        if !ambiguous.isEmpty { parts.append("\(ambiguous.count.formatted()) ambiguous") }
        if unmatchedCount > 0 { parts.append("\(unmatchedCount.formatted()) not in Photos") }
        if !notEditable.isEmpty { parts.append("\(notEditable.count.formatted()) read-only") }
        return parts.joined(separator: " · ")
    }

    /// Rows the person decided themselves.
    public var manualOverrides: [PlannedChange] { changes.filter(\.isManualOverride) }

    /// Overrides one row, whatever planning decided.
    public mutating func setRating(_ rating: Int?, for changeID: String) {
        guard let index = changes.firstIndex(where: { $0.id == changeID }) else { return }
        changes[index].newRating = rating
        changes[index].isManualOverride = true
    }

    /// Answers every row that was put to you by taking Lightroom's rating.
    ///
    /// Every such row, not only the ones still unanswered. Answering only the
    /// remainder would mean the first of these two calls settled the question
    /// for good: with nothing left unanswered, the other one had nothing to
    /// act on, and changing your mind was impossible without clicking through
    /// the rows one at a time.
    ///
    /// So each is a statement about the whole set, as its label on screen
    /// says, and pressing the other one turns the lot back over. Per-row
    /// choices made beforehand go with them — which is the price of being
    /// able to say "no, the other way" in one click, and is recoverable,
    /// since nothing here writes anything.
    public mutating func takeAllFromLightroom() {
        for index in changes.indices where changes[index].needsReview {
            changes[index].newRating = changes[index].asset.rating
            changes[index].isManualOverride = true
        }
    }

    /// Answers every row that was put to you by leaving Photos as it is.
    ///
    /// The mirror of `takeAllFromLightroom`, with the same reach.
    public mutating func keepAllFromPhotos() {
        for index in changes.indices where changes[index].needsReview {
            changes[index].newRating = changes[index].photo.rating
            changes[index].isManualOverride = true
        }
    }
}

/// What to do with a planned row once the live rating in Photos is known.
///
/// A plan is built from a snapshot, and Photos keeps changing after that: the
/// person can rate a photo in Photos.app while the preview sits on screen, or
/// while a long run is still writing. Every row is therefore checked once more
/// against the live rating immediately before it is written.
public enum RecheckOutcome: Sendable, Equatable {
    /// Write this rating.
    case write(Int)
    /// Nothing to do — Photos already holds the intended rating.
    case alreadyCorrect
    /// Photos changed since the preview, so the row is left alone and
    /// reported rather than overwritten.
    case changedInPhotos(liveRating: Int)
    /// Lightroom changed since the preview, so what the row was going to
    /// write is no longer what Lightroom says. Left alone and reported.
    case changedInLightroom(liveRating: Int)
}

public enum SyncPlanner {
    /// Turns a match report into a plan.
    ///
    /// Photos with no rating in Photos are filled in automatically. Where both
    /// sides hold a rating and they differ, nothing is decided here: the row is
    /// held for the person, because five stars against four is not a call this
    /// code is in a position to make.
    ///
    /// A Lightroom photo at 0★ is always left alone. Zero means "not triaged
    /// yet", so it is never allowed to clear a rating that exists in Photos.
    public static func plan(from report: MatchReport) -> SyncPlan {
        var changes: [PlannedChange] = []

        for match in report.matches {
            guard let photo = match.photo else { continue }
            changes.append(decide(asset: match.asset, photo: photo))
        }

        // Sorted once, here, rather than every time a view draws the list.
        // The screen shows a couple of thousand rows and re-renders on every
        // star click, and a localized sort of that many names is slow enough
        // to feel. Filtering preserves order, so every subset is sorted too.
        changes.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        return SyncPlan(
            changes: changes,
            unmatchedCount: report.notInPhotos.count,
            // See `SyncPlan.ambiguous`: an unrated photo's ambiguity changes
            // nothing, so it is not worth putting in front of anyone.
            ambiguous: report.ambiguous.filter { $0.asset.isRated }
        )
    }

    static func decide(asset: LRAsset, photo: PhotoAsset) -> PlannedChange {
        // 0★ in Lightroom means not yet triaged. It never clears a rating.
        guard asset.isRated else {
            return PlannedChange(
                asset: asset, photo: photo,
                reason: .notRatedInLightroom, newRating: nil, needsReview: false
            )
        }

        if asset.rating == photo.rating {
            return PlannedChange(
                asset: asset, photo: photo,
                reason: .alreadyMatches, newRating: nil, needsReview: false
            )
        }

        // Nothing can be written here, so report it rather than planning a
        // write that would fail at apply time.
        guard photo.isEditable else {
            return PlannedChange(
                asset: asset, photo: photo,
                reason: .notEditable, newRating: nil, needsReview: false
            )
        }

        guard photo.rating > 0 else {
            // Photos has no rating: fill it in.
            return PlannedChange(
                asset: asset, photo: photo,
                reason: .newRating, newRating: asset.rating, needsReview: false
            )
        }

        // Both sides rated, and they disagree. The person decides.
        return PlannedChange(
            asset: asset, photo: photo,
            reason: .conflict, newRating: nil, needsReview: true
        )
    }

    /// Checks one planned row against both libraries as they are right now.
    ///
    /// This is the only staleness check there is. Both libraries are read when
    /// the app opens and not again, so by the time anything is written the
    /// plan can be any age at all — which is fine, because nothing is written
    /// without passing through here first.
    ///
    /// `lightroomRating` is the rating Lightroom holds for this photo now, or
    /// `nil` when the catalog is known not to have changed since it was read
    /// and there is nothing to compare against.
    ///
    /// A row whose either side has moved is left alone and reported. Filling in
    /// a blank is the only thing this code does on its own initiative, and it
    /// will not do it from a rating Lightroom no longer gives, or over a blank
    /// that is no longer blank.
    public static func recheck(
        _ change: PlannedChange,
        liveRating: Int,
        lightroomRating: Int? = nil
    ) -> RecheckOutcome {
        guard let intended = change.newRating else { return .alreadyCorrect }

        // Already where it needs to be, whoever put it there.
        if liveRating == intended { return .alreadyCorrect }

        // An explicit choice stands, whichever side moved underneath it. The
        // person named this rating; the comparison they were shown going out
        // of date does not withdraw their instruction. The undo log records
        // the live value, so this stays reversible.
        if change.isManualOverride { return .write(intended) }

        // Lightroom changed underneath the preview. Checked before Photos
        // because this is where the intended rating came from: if the source
        // has moved, the row is stale no matter what Photos holds.
        //
        // This also covers a rating taken back down to 0★ in Lightroom, which
        // differs from what was planned and so is skipped rather than written
        // — safety rule 5, arrived at here for free.
        if let now = lightroomRating, now != change.asset.rating {
            return .changedInLightroom(liveRating: now)
        }

        // Photos still holds what the preview showed: no interference.
        if liveRating == change.photo.rating { return .write(intended) }

        return .changedInPhotos(liveRating: liveRating)
    }
}
