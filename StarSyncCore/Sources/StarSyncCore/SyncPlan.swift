import Foundation

/// How a run treats photos that already carry a rating in Apple Photos.
///
/// Every preset leaves a Lightroom photo at 0★ alone: in Lightroom, zero
/// means "not triaged yet", so it is never allowed to clear a rating that
/// exists in Photos.
public enum SyncMode: String, Sendable, CaseIterable, Identifiable {
    /// Fill in ratings where Photos has none. Never changes an existing one.
    ///
    /// This also covers "don't overwrite when there's a mismatch" — both
    /// requests describe the same write set.
    case addOnly
    /// Lightroom is the source of truth: overwrite a differing rating.
    case lightroomWins
    /// Fill in the blanks automatically, and collect every mismatch for
    /// review rather than deciding it.
    case reviewConflicts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .addOnly: return "Add only"
        case .lightroomWins: return "Lightroom wins"
        case .reviewConflicts: return "Review conflicts"
        }
    }

    public var explanation: String {
        switch self {
        case .addOnly:
            return "Rate photos that have no rating in Photos yet. Anything already rated is left untouched."
        case .lightroomWins:
            return "Make Photos match Lightroom, replacing ratings that differ. Photos rated in Photos but not in Lightroom keep their rating."
        case .reviewConflicts:
            return "Rate the photos that have no rating yet, and ask about each one where Lightroom and Photos disagree."
        }
    }
}

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
public struct PlannedChange: Sendable, Identifiable {
    public let asset: LRAsset
    public let photo: PhotoAsset
    public let reason: ChangeReason
    /// The rating to write, or nil to leave the photo as it is.
    public var newRating: Int?
    /// True when the mode deferred this to the person rather than deciding.
    public let needsReview: Bool

    public var id: String { asset.id }
    public var lightroomRating: Int { asset.rating }
    public var photosRating: Int { photo.rating }

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
        needsReview: Bool
    ) {
        self.asset = asset
        self.photo = photo
        self.reason = reason
        self.newRating = newRating
        self.needsReview = needsReview
    }
}

/// Everything a run intends to do, ready to show before anything is written.
public struct SyncPlan: Sendable {
    public let mode: SyncMode
    public var changes: [PlannedChange]
    /// Lightroom photos with no counterpart in Photos.
    public let unmatchedCount: Int
    /// Lightroom photos whose counterpart could not be identified uniquely.
    public let ambiguous: [Match]

    public init(mode: SyncMode, changes: [PlannedChange], unmatchedCount: Int, ambiguous: [Match]) {
        self.mode = mode
        self.changes = changes
        self.unmatchedCount = unmatchedCount
        self.ambiguous = ambiguous
    }

    public var writes: [PlannedChange] { changes.filter(\.willWrite) }
    public var conflicts: [PlannedChange] { changes.filter { $0.reason == .conflict } }
    public var pendingReview: [PlannedChange] { changes.filter { $0.needsReview && $0.newRating == nil } }
    public var notEditable: [PlannedChange] { changes.filter { $0.reason == .notEditable } }

    public var summary: String {
        var parts = ["\(writes.count) to write"]
        if !conflicts.isEmpty { parts.append("\(conflicts.count) conflicts") }
        if !ambiguous.isEmpty { parts.append("\(ambiguous.count) ambiguous") }
        if unmatchedCount > 0 { parts.append("\(unmatchedCount) not in Photos") }
        if !notEditable.isEmpty { parts.append("\(notEditable.count) read-only") }
        return parts.joined(separator: " · ")
    }

    /// Overrides one row, whatever the mode decided.
    public mutating func setRating(_ rating: Int?, for changeID: String) {
        guard let index = changes.firstIndex(where: { $0.id == changeID }) else { return }
        changes[index].newRating = rating
    }

    /// Resolves every row still awaiting review by taking Lightroom's rating.
    public mutating func resolveAllRemainingFromLightroom() {
        for index in changes.indices where changes[index].needsReview && changes[index].newRating == nil {
            changes[index].newRating = changes[index].asset.rating
        }
    }

    /// Leaves every row still awaiting review as Photos has it.
    public mutating func keepAllRemainingFromPhotos() {
        for index in changes.indices where changes[index].needsReview && changes[index].newRating == nil {
            changes[index].newRating = changes[index].photo.rating
        }
    }
}

public enum SyncPlanner {
    /// Turns a match report into a plan under the chosen mode.
    public static func plan(from report: MatchReport, mode: SyncMode) -> SyncPlan {
        var changes: [PlannedChange] = []

        for match in report.matches {
            guard let photo = match.photo else { continue }
            changes.append(decide(asset: match.asset, photo: photo, mode: mode))
        }

        return SyncPlan(
            mode: mode,
            changes: changes,
            unmatchedCount: report.notInPhotos.count,
            ambiguous: report.ambiguous
        )
    }

    static func decide(asset: LRAsset, photo: PhotoAsset, mode: SyncMode) -> PlannedChange {
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

        let photosHasRating = photo.rating > 0
        let reason: ChangeReason = photosHasRating ? .conflict : .newRating

        switch (mode, photosHasRating) {
        case (_, false):
            // Photos has no rating: every mode fills it in.
            return PlannedChange(
                asset: asset, photo: photo,
                reason: reason, newRating: asset.rating, needsReview: false
            )
        case (.addOnly, true):
            return PlannedChange(
                asset: asset, photo: photo,
                reason: reason, newRating: nil, needsReview: false
            )
        case (.lightroomWins, true):
            return PlannedChange(
                asset: asset, photo: photo,
                reason: reason, newRating: asset.rating, needsReview: false
            )
        case (.reviewConflicts, true):
            return PlannedChange(
                asset: asset, photo: photo,
                reason: reason, newRating: nil, needsReview: true
            )
        }
    }
}
