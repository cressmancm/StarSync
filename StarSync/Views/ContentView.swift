import StarSyncCore
import SwiftUI

struct ContentView: View {
    @State private var controller = SyncController()

    var body: some View {
        VStack(spacing: 0) {
            StepBar(current: controller.step)
            Divider()

            Group {
                switch controller.step {
                case .source: SourceStepView(controller: controller)
                case .preview: PreviewStepView(controller: controller)
                case .apply: ApplyStepView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if controller.step != .apply {
                Divider()
                footer
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .task {
            // Pick the library back up where it was left, so the common case
            // is opening the app and pressing Continue. Not if the last read
            // never finished: that read may be what stopped the app, and
            // repeating it here would stop it again on every launch.
            if controller.libraryURL != nil, controller.catalog == nil,
               !controller.lastReadDidNotFinish {
                await controller.load()
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK") { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if controller.isWorking {
                ProgressView(value: controller.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 130)
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Rows still waiting on a decision are skipped, not blocked. Say
            // so here rather than letting them disappear quietly.
            if controller.step == .preview,
               let pending = controller.plan?.pendingReview.count, pending > 0 {
                Text("\(pending.formatted()) left undecided will be skipped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("Photos you haven't decided on are skipped. You can sync again to decide them.")
            }

            if controller.step != .source {
                Button("Back") { goBack() }
                    .disabled(controller.isWorking)
            }

            Button(primaryTitle) { Task { await goForward() } }
                .buttonStyle(.borderedProminent)
                .disabled(!canGoForward)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var primaryTitle: String {
        switch controller.step {
        case .source: return "Continue"
        case .preview:
            let count = controller.plan?.writes.count ?? 0
            return count == 0 ? "Nothing to write" : "Write \(count.formatted()) rating\(count == 1 ? "" : "s")"
        case .apply: return "Done"
        }
    }

    private var canGoForward: Bool {
        guard !controller.isWorking else { return false }
        switch controller.step {
        // The scope check used to gate the mode step. With that step gone it
        // belongs here: an album with nothing in it has nothing to plan.
        case .source:
            return controller.catalog != nil && controller.photos != nil
                && !controller.scopedAssets.isEmpty
        case .preview: return (controller.plan?.writes.count ?? 0) > 0
        case .apply: return true
        }
    }

    private func goBack() {
        switch controller.step {
        case .source: break
        case .preview: controller.step = .source
        case .apply: controller.step = .preview
        }
    }

    private func goForward() async {
        switch controller.step {
        // buildPlan sets the step itself on success, so a failure leaves you
        // here rather than on an empty Review screen.
        case .source: await controller.buildPlan()
        case .preview: await controller.apply()
        case .apply: controller.reset()
        }
    }
}

/// The three steps, with the current one marked.
private struct StepBar: View {
    let current: SyncController.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(SyncController.Step.allCases.enumerated()), id: \.element) { index, step in
                HStack(spacing: 5) {
                    Image(systemName: symbol(for: step, at: index))
                        .font(.system(size: 13))
                        .foregroundStyle(step.rawValue <= current.rawValue
                                         ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    Text(step.title)
                        .font(.callout.weight(step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
                if index < SyncController.Step.allCases.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func symbol(for step: SyncController.Step, at index: Int) -> String {
        step.rawValue < current.rawValue
            ? "checkmark.circle.fill"
            : "\(index + 1).circle\(step == current ? ".fill" : "")"
    }
}

extension SyncController.Step: Hashable {}
