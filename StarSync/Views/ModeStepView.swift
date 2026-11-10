import StarSyncCore
import SwiftUI

/// Step two: how to treat photos that already carry a rating in Photos.
struct ModeStepView: View {
    @Bindable var controller: SyncController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Syncing \(controller.scopeDescription)")
                    .font(.headline)
                Text("\(ratedInScope.formatted()) of \(controller.scopedAssets.count.formatted()) photos are rated in Lightroom.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(SyncMode.allCases) { mode in
                modeCard(mode)
            }

            Label(
                "A photo left unrated in Lightroom is always skipped — it never clears a rating you set in Photos.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            Spacer()
        }
        .padding(16)
    }

    private var ratedInScope: Int {
        controller.scopedAssets.count(where: \.isRated)
    }

    private func modeCard(_ mode: SyncMode) -> some View {
        let selected = controller.mode == mode
        return Button {
            controller.mode = mode
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.body.weight(.medium))
                    Text(mode.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.07) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.22))
            )
        }
        .buttonStyle(.plain)
    }
}
