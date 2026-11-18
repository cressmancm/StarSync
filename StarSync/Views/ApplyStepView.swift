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
                     ? "There was nothing to put back."
                     : "Put \(reverted.formatted()) rating\(reverted == 1 ? "" : "s") back.")
                    .font(.title3.weight(.medium))
            } else if let result = controller.applyResult {
                let clean = result.failed.isEmpty && result.skipped.isEmpty
                Image(systemName: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(clean ? Color.accentColor : .orange)

                Text(result.written == 0
                     ? "There was nothing to change."
                     : "Wrote \(result.written.formatted()) rating\(result.written == 1 ? "" : "s") to Photos.")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)

                if !result.skipped.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.skipped.count) left alone because they changed after you reviewed them:")
                            .font(.callout.weight(.medium))
                        ForEach(Array(result.skipped.prefix(6).enumerated()), id: \.offset) { _, skip in
                            NamedLine(name: skip.filename, note: skip.note)
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
                            NamedLine(name: failure.filename, note: failure.reason)
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
                    .help("Puts every rating back to what it was before this sync.")
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

/// One photo this run could not settle, named first and then explained.
///
/// The name is drawn on its own so it can be selected and copied, because
/// every line in these two lists is telling you to go and look at that photo
/// in Lightroom or in Photos — and the first thing you do there is search for
/// it by name.
///
/// The name keeps its width and the explanation gives way around it: a name
/// cut in half is useless, while a failure reason from PhotoKit can run long
/// and reads perfectly well wrapped onto a second line, which is what it did
/// before it had a name beside it.
private struct NamedLine: View {
    let name: String
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            FileNameText(name: name)
                .layoutPriority(1)
            Text("— \(note)")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
