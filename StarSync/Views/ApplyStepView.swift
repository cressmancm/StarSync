import SwiftUI

/// Step four: what happened, and the way back.
struct ApplyStepView: View {
    @Bindable var controller: SyncController

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            if let reverted = controller.revertedCount {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(reverted == 0
                     ? "Nothing needed putting back."
                     : "Put \(reverted.formatted()) rating\(reverted == 1 ? "" : "s") back.")
                    .font(.title3.weight(.medium))
            } else if let result = controller.applyResult {
                let clean = result.failed.isEmpty && result.skipped.isEmpty
                Image(systemName: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(clean ? Color.accentColor : .orange)

                Text(result.written == 0
                     ? "Nothing needed changing."
                     : "Wrote \(result.written.formatted()) rating\(result.written == 1 ? "" : "s") to Photos.")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)

                if !result.skipped.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.skipped.count) left alone — rated in Photos after the preview was built:")
                            .font(.callout.weight(.medium))
                        ForEach(Array(result.skipped.prefix(6).enumerated()), id: \.offset) { _, skip in
                            Text("\(skip.filename) — Photos has \(skip.liveRating)★, Lightroom has \(skip.plannedRating)★")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if result.skipped.count > 6 {
                            Text("and \(result.skipped.count - 6) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text("Sync again to decide what these should be.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: 400, alignment: .leading)
                    .padding(11)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                }

                if !result.failed.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.failed.count) could not be written:")
                            .font(.callout.weight(.medium))
                        ForEach(Array(result.failed.prefix(6).enumerated()), id: \.offset) { _, failure in
                            Text("\(failure.filename) — \(failure.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if result.failed.count > 6 {
                            Text("and \(result.failed.count - 6) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: 400, alignment: .leading)
                    .padding(11)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            HStack(spacing: 10) {
                if let run = controller.lastRun, run.writeCount > 0 {
                    Button("Revert this sync") {
                        Task { await controller.revertLastRun() }
                    }
                    .disabled(controller.isWorking)
                    .help("Puts every rating back to what it was before this run.")
                }
                Button("Sync more photos") { controller.reset() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isWorking)
            }
            .padding(.top, 2)

            if !controller.statusMessage.isEmpty {
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}
