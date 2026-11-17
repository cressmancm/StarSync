import StarSyncCore
import SwiftUI

/// Step three: everything that is about to happen, with a way to change any
/// single row before anything is written.
struct PreviewStepView: View {
    @Bindable var controller: SyncController

    /// The buckets the review list is divided into.
    ///
    /// Deliberately not called `Section` or `Group`: both shadow SwiftUI types
    /// used a few lines below, and the diagnostics are baffling.
    ///
    /// The order is the order of the work: what is being asked of you, then
    /// what will happen, then the two kinds of nothing — the photos the app
    /// could not tell apart, and the much longer list it is leaving alone.
    /// Only the last of those is collapsed by default, because it is the one
    /// nobody needs to read.
    private enum RowGroup: String, CaseIterable, Identifiable {
        case needsDecision, willWrite, ambiguous, leavingAlone
        var id: String { rawValue }

        var title: String {
            switch self {
            case .needsDecision: return "Needs your decision"
            case .willWrite: return "Will write"
            case .ambiguous: return "Matched more than one photo"
            case .leavingAlone: return "Leaving alone"
            }
        }
    }

    @State private var expanded: Set<RowGroup> = [.needsDecision, .willWrite, .ambiguous]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if plan == nil || plan?.changes.isEmpty == true {
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
            if let plan {
                Text(plan.summary)
                    .font(.headline)
                    .monospacedDigit()
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Grouping

    /// Which section a row lives in, decided by what planning found rather
    /// than by what the row is currently going to do.
    ///
    /// `reason` is set when the plan is built and never changes afterwards, so
    /// a row cannot move however you edit it. That is the point. Grouping by
    /// the outcome meant a row left the list from under the cursor the instant
    /// you clicked a star — no chance to see what you had just done, let alone
    /// check it — and pressing "Keep all from Photos" emptied a whole section
    /// in one go. Being able to look back over what you changed matters more
    /// than filing each row under its eventual fate, which the row says for
    /// itself in its badge and in the line beside its stars.
    private static func section(for reason: ChangeReason) -> RowGroup {
        switch reason {
        case .conflict: return .needsDecision
        case .newRating: return .willWrite
        case .alreadyMatches, .notRatedInLightroom, .notEditable: return .leavingAlone
        }
    }

    private func belongs(_ change: PlannedChange, to group: RowGroup) -> Bool {
        // `ambiguous` holds no planned changes at all — those rows come from
        // `plan.ambiguous`, which is `[Match]`, since there is no single photo
        // to plan against.
        group != .ambiguous && Self.section(for: change.reason) == group
    }

    private func count(for group: RowGroup) -> Int {
        if group == .ambiguous { return plan?.ambiguous.count ?? 0 }
        // count(where:) rather than filter().count — no need to copy a
        // couple of thousand rows just to size a header.
        return plan?.changes.count(where: { belongs($0, to: group) }) ?? 0
    }

    /// Already in display order: `SyncPlanner.plan` sorts `changes` by name,
    /// and filtering keeps that order.
    private func rows(for group: RowGroup) -> [PlannedChange] {
        plan?.changes.filter { belongs($0, to: group) } ?? []
    }

    private var visibleGroups: [RowGroup] {
        RowGroup.allCases.filter { count(for: $0) > 0 }
    }

    private func isExpanded(_ group: RowGroup) -> Bool {
        // A lone group cannot be collapsed into an empty screen.
        expanded.contains(group) || visibleGroups.count == 1
    }

    private func toggle(_ group: RowGroup) {
        // No animation: inserting or removing a couple of thousand rows inside
        // an animated transaction stutters badly. Only the chevron animates.
        if expanded.contains(group) {
            expanded.remove(group)
        } else {
            expanded.insert(group)
        }
    }

    /// The line under a section heading: how far through it you are, and the
    /// breakdown under "Leaving alone", which survives that section being
    /// collapsed — as it is by default.
    private func subtitle(for group: RowGroup) -> String? {
        if group == .ambiguous {
            return "Nothing will be written to these. They are usually virtual copies."
        }

        if group == .needsDecision, let plan {
            let waiting = plan.pendingReview.count
            let decided = count(for: .needsDecision) - waiting
            if decided == 0 { return nil }
            if waiting == 0 { return "All \(decided.formatted()) decided" }
            return "\(decided.formatted()) decided · \(waiting.formatted()) still waiting"
        }

        // Rows stay where planning put them, so this section is no longer the
        // list of everything that will write: a row you decided above, or
        // rated down below, writes from where it sits. Give the real total
        // rather than leaving two numbers on screen to disagree.
        if group == .willWrite, let plan {
            let here = plan.changes.count(where: { belongs($0, to: .willWrite) && $0.willWrite })
            guard here != plan.writes.count else { return nil }
            return "\(plan.writes.count.formatted()) will write in all"
        }

        guard group == .leavingAlone, let plan else { return nil }
        var matches = 0, notRated = 0, readOnly = 0, nowWriting = 0
        for change in plan.changes where belongs(change, to: .leavingAlone) {
            // Rated by hand since, so this section's name no longer covers it.
            // Called out here as well as on the row, because this is the one
            // section that is collapsed by default.
            if change.willWrite { nowWriting += 1 }
            switch change.reason {
            case .alreadyMatches: matches += 1
            case .notRatedInLightroom: notRated += 1
            case .notEditable: readOnly += 1
            // Filed elsewhere by `section(for:)`, and listed here only so the
            // switch covers every reason there is.
            case .newRating, .conflict: break
            }
        }
        var parts: [String] = []
        if matches > 0 { parts.append("\(matches.formatted()) already match") }
        if notRated > 0 { parts.append("\(notRated.formatted()) not rated in Lightroom") }
        if readOnly > 0 { parts.append("\(readOnly.formatted()) read-only") }
        if nowWriting > 0 { parts.append("\(nowWriting.formatted()) you set to write") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Rows

    private var rowList: some View {
        List {
            ForEach(visibleGroups) { group in
                Section {
                    GroupHeaderRow(
                        title: group.title,
                        count: count(for: group),
                        subtitle: subtitle(for: group),
                        isExpanded: isExpanded(group),
                        toggle: { toggle(group) }
                    ) {
                        if group == .needsDecision {
                            Button("Take all from Lightroom") { controller.takeAllFromLightroom() }
                            Button("Keep all from Photos") { controller.keepAllFromPhotos() }
                        }
                    }
                    .listRowSeparator(.hidden)

                    if isExpanded(group) {
                        if group == .ambiguous {
                            ForEach(plan?.ambiguous ?? []) { match in
                                AmbiguousRow(match: match)
                                    .padding(.vertical, 2)
                            }
                        } else {
                            ForEach(rows(for: group)) { change in
                                PreviewRow(
                                    change: change,
                                    onSet: { controller.setRating($0, for: change.id) }
                                )
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
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
            Text("No photos in this selection could be matched to your Photos library.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Spacer()
        }
    }
}

/// A section header that is a list row: a disclosure button on the left, and
/// whatever actions the section needs as its siblings on the right.
///
/// The chevron is drawn here rather than using `Section(isExpanded:)` because
/// that API's disclosure affordance is tied to the sidebar list style, and
/// sidebar does not draw the alternating row backgrounds this table wants.
private struct GroupHeaderRow<Trailing: View>: View {
    let title: String
    let count: Int
    let subtitle: String?
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeOut(duration: 0.15), value: isExpanded)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(title) (\(count.formatted()))")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("\(title), \(count) photo\(count == 1 ? "" : "s")")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides these photos")

            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 2)
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
                FileNameText(
                    name: change.displayName,
                    lightroomName: change.asset.fileName
                )
                .font(.body)
                HStack(spacing: 7) {
                    ActionBadge(
                        text: change.badgeText,
                        tone: change.badgeTone,
                        symbol: change.badgeSymbol
                    )
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

/// A Lightroom photo that matched more than one photo in Photos, with the
/// photos it could not be told apart between.
///
/// Nothing is written for these, so there is no picker and no decision to
/// make. They are listed rather than counted because a count cannot be checked
/// against anything: seeing the candidates side by side is the only way to
/// tell a pair of virtual copies, which is the usual and harmless cause, from
/// matching that has gone wrong.
private struct AmbiguousRow: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                FileNameText(name: match.asset.fileName)
                    .font(.body)
                ActionBadge(
                    text: "\(match.candidates.count) possible matches",
                    tone: .neutral
                )
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Text("Lightroom")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    StarRatingView(
                        rating: match.asset.rating,
                        dimmed: match.asset.rating == 0
                    )
                }
            }

            ForEach(match.candidates) { candidate in
                HStack(spacing: 8) {
                    ThumbnailView(localIdentifier: candidate.id, side: 36)
                    FileNameText(name: candidate.originalFilename ?? "No file name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    StarRatingView(rating: candidate.rating, dimmed: candidate.rating == 0)
                }
            }
            .padding(.leading, 10)
        }
    }
}

// MARK: - Row presentation

extension PlannedChange {
    /// A row that was put to you and that you have since answered.
    ///
    /// It keeps its place in "Needs your decision" and says so here instead,
    /// so the section reads as a record of what you did rather than emptying
    /// itself as you work down it.
    var isDecided: Bool { needsReview && newRating != nil }

    /// A row you changed by hand, in a section that was not asking you to.
    ///
    /// Rows stay where planning put them, so one you rate yourself sits under
    /// a heading that no longer describes it — a photo under "Leaving alone"
    /// that is now going to be written. The badge has to say so, since the
    /// heading above it does not.
    var isYourChange: Bool { isManualOverride && !needsReview }

    var badgeText: String {
        if isDecided { return "Decided" }
        if isYourChange { return willWrite ? "Will write" : "Leaving alone" }
        switch reason {
        case .newRating: return "New rating"
        case .conflict: return "Conflict"
        case .alreadyMatches: return "Already matches"
        case .notRatedInLightroom: return "Not rated in Lightroom"
        case .notEditable: return "Read-only"
        }
    }

    var badgeTone: ActionBadge.Tone {
        if isDecided { return .decided }
        if isYourChange { return willWrite ? .write : .neutral }
        switch reason {
        case .newRating: return .write
        case .conflict: return .conflict
        case .alreadyMatches, .notRatedInLightroom: return .neutral
        case .notEditable: return .blocked
        }
    }

    /// A tick on every row you touched — answered, or rated yourself — so a
    /// section can be scanned for your own marks without reading a word of it.
    var badgeSymbol: String? { isDecided || isYourChange ? "checkmark" : nil }

    var outcomeText: String {
        if !photo.isEditable { return "Cannot change" }
        if needsReview && newRating == nil { return "Waiting on you" }
        guard let newRating else { return "Leave as is" }
        if newRating == photo.rating { return "No change" }
        return newRating == 0 ? "Clear rating" : "Write \(newRating)★"
    }
}
