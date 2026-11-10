import Photos
import SwiftUI

/// A small preview of a photo, loaded from Photos on demand.
///
/// Seeing the photo is the point of the review step: deciding between four
/// stars and five from a file name alone is not really deciding.
struct ThumbnailView: View {
    let localIdentifier: String
    var side: CGFloat = 52

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                if failed {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: localIdentifier) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let target = CGSize(width: side * scale, height: side * scale)

        guard let asset = PhotosLibrary.assets(withIdentifiers: [localIdentifier])[localIdentifier] else {
            failed = true
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let loaded: NSImage? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Opportunistic delivery can call back twice; only the
                // final, non-degraded result should resume the continuation.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }

        if let loaded {
            image = loaded
        } else {
            failed = true
        }
    }
}
