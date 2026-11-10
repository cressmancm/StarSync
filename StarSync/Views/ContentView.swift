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
                case .mode: ModeStepView(controller: controller)
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
            // is opening the app and pressing Continue.
            if controller.libraryURL != nil, controller.catalog == nil {
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
        case .source, .mode: return "Continue"
        case .preview:
            let count = controller.plan?.writes.count ?? 0
            return count == 0 ? "Nothing to write" : "Write \(count.formatted()) rating\(count == 1 ? "" : "s")"
        case .apply: return "Done"
        }
    }

    private var canGoForward: Bool {
        guard !controller.isWorking else { return false }
        switch controller.step {
        case .source: return controller.catalog != nil && controller.photos != nil
        case .mode: return !controller.scopedAssets.isEmpty
        case .preview: return (controller.plan?.writes.count ?? 0) > 0
        case .apply: return true
        }
    }

    private func goBack() {
        switch controller.step {
        case .source: break
        case .mode: controller.step = .source
        case .preview: controller.step = .mode
        case .apply: controller.step = .preview
        }
    }

    private func goForward() async {
        switch controller.step {
        case .source: controller.step = .mode
        case .mode: await controller.buildPlan()
        case .preview: await controller.apply()
        case .apply: controller.reset()
        }
    }
}

/// The four steps, with the current one marked.
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
