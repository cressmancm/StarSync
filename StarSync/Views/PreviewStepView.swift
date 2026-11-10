import StarSyncCore
import SwiftUI

/// Step three: everything that is about to happen, with a way to change any
/// single row before anything is written.
struct PreviewStepView: View {
    @Bindable var controller: SyncController
    @State private var filter: Filter = .needsAttention

    enum Filter: String, CaseIterable, Identifiable {
        case needsAttention, willWrite, everything
        var id: String { rawValue }

        var title: String {
            switch self {
            case .needsAttention: return "Needs attention"
            case .willWrite: return "Will write"
            case .everything: return "All photos"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                rowList
            }
        }
    }

    private var plan: SyncPlan? { controller.plan }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.photosChangedSincePlan {
                staleNotice
            }

            if let plan {
                Text(plan.summary)
                    .font(.headline)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if let plan, !plan.pendingReview.isEmpty {
                    Text("\(plan.pendingReview.count) to decide")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Take all from Lightroom") { controller.takeAllFromLightroom() }
                    Button("Keep all from Photos") { controller.keepAllFromPhotos() }
                }
            }

            if let plan, !plan.ambiguous.isEmpty {
                Label(
                    "\(plan.ambiguous.count) Lightroom photos matched more than one photo in Photos and were left out. They are usually virtual copies.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let plan, !plan.notEditable.isEmpty {
                Label(
                    "\(plan.notEditable.count) photos cannot be changed by StarSync, usually because they come from a shared library.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Shown when Photos changed while this preview was on screen.
    ///
    /// Applying anyway is safe — every row is checked against the live rating
    /// before it is written — so this informs rather than blocks. Rebuilding
    /// is offered instead of done automatically, because reshuffling the table
    /// under someone who is reading it, and throwing away the choices they
    /// have made in it, is not an improvement.
    private var staleNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ratings in Photos have changed since this preview was built.")
                    .font(.callout.weight(.medium))
                Text(rebuildCost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rebuild") {
                Task { await controller.buildPlan() }
            }
            .disabled(controller.isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var rebuildCost: String {
        let overrides = plan?.manualOverrides.count ?? 0
        guard overrides > 0 else {
            return "The rows below may be out of date. Nothing already rated in Photos will be overwritten."
        }
        return "Rebuilding will discard the \(overrides) rating\(overrides == 1 ? "" : "s") you have set here."
    }

    // MARK: Rows

    private var rows: [PlannedChange] {
        guard let plan else { return [] }
        let subset: [PlannedChange]
        switch filter {
        case .needsAttention:
            subset = plan.changes.filter { $0.needsReview || $0.reason == .conflict || $0.reason == .notEditable }
        case .willWrite:
            subset = plan.writes
        case .everything:
            subset = plan.changes
        }
        // Rows that want a decision come first, then conflicts, then writes.
        return subset.sorted { a, b in
            if a.sortRank != b.sortRank { return a.sortRank < b.sortRank }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    private var rowList: some View {
        List(rows) { change in
            PreviewRow(
                change: change,
                onSet: { controller.setRating($0, for: change.id) }
            )
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Spacer()
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .needsAttention:
            return "Nothing needs a decision."
        case .willWrite:
            return "No ratings need writing — Photos already matches Lightroom for these photos."
        case .everything:
            return "No photos in this selection could be matched to your Photos library."
        }
    }
}

/// One photo in the review list.
private struct PreviewRow: View {
    let change: PlannedChange
    let onSet: (Int?) -> Void

    var body: some View {
        HStack(spacing: 11) {
            ThumbnailView(localIdentifier: change.photo.id)

            VStack(alignment: .leading, spacing: 3) {
                Text(change.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 7) {
                    ActionBadge(text: change.badgeText, tone: change.badgeTone)
                    if let flag = change.asset.flag {
                        Text(flag.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer(minLength: 8)

            // Lightroom's rating, then Photos', then what will be written.
            VStack(alignment: .trailing, spacing: 3) {
                labelled("Lightroom", rating: change.lightroomRating)
                labelled("Photos", rating: change.photosRating)
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                StarRatingPicker(
                    rating: Binding(
                        get: { change.newRating ?? change.photo.rating },
                        set: { onSet($0) }
                    )
                )
                .disabled(!change.photo.isEditable)
                Text(change.outcomeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 104, alignment: .leading)
        }
    }

    private func labelled(_ title: String, rating: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            StarRatingView(rating: rating, dimmed: rating == 0)
        }
    }
}

// MARK: - Row presentation

extension PlannedChange {
    var sortRank: Int {
        if needsReview && newRating == nil { return 0 }
        if reason == .conflict { return 1 }
        if reason == .notEditable { return 2 }
        if willWrite { return 3 }
        return 4
    }

    var badgeText: String {
        switch reason {
        case .newRating: return "New rating"
        case .conflict: return "Conflict"
        case .alreadyMatches: return "Already matches"
        case .notRatedInLightroom: return "Not rated in Lightroom"
        case .notEditable: return "Read-only"
        }
    }

    var badgeTone: ActionBadge.Tone {
        switch reason {
        case .newRating: return .write
        case .conflict: return .conflict
        case .alreadyMatches, .notRatedInLightroom: return .neutral
        case .notEditable: return .blocked
        }
    }

    var outcomeText: String {
        if !photo.isEditable { return "Cannot change" }
        if needsReview && newRating == nil { return "Waiting on you" }
        guard let newRating else { return "Leave as is" }
        if newRating == photo.rating { return "No change" }
        return newRating == 0 ? "Clear rating" : "Write \(newRating)★"
    }
}
