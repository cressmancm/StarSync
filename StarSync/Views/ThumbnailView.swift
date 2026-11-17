import os
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

        // Shared between PhotoKit's callback and SwiftUI's cancellation, which
        // arrive on different threads. Whichever finishes first takes the
        // continuation, so it is resumed exactly once, and a row scrolled off
        // screen gives its request back instead of waiting on it forever.
        let state = OSAllocatedUnfairLock(initialState: RequestState())
        let manager = PHImageManager.default()

        let loaded: NSImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Stored before the request, in case PhotoKit calls back
                // before `requestImage` has even returned.
                state.withLock { $0.continuation = continuation }
                let id = manager.requestImage(
                    for: asset,
                    targetSize: target,
                    contentMode: .aspectFill,
                    options: options
                ) { image, info in
                    // Opportunistic delivery can call back twice; only the
                    // final result should resume the continuation. An error
                    // or a cancellation is final too, and may be the only
                    // callback there is, so it must not be waited past.
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let errored = info?[PHImageErrorKey] != nil
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard cancelled || errored || !degraded else { return }
                    state.takeContinuation()?.resume(returning: cancelled ? nil : image)
                }
                let cancelledAlready = state.withLock { state in
                    state.id = id
                    return state.cancelled
                }
                if cancelledAlready {
                    manager.cancelImageRequest(id)
                    state.takeContinuation()?.resume(returning: nil)
                }
            }
        } onCancel: {
            let id = state.withLock { state in
                state.cancelled = true
                return state.id
            }
            if let id { manager.cancelImageRequest(id) }
            state.takeContinuation()?.resume(returning: nil)
        }

        guard !Task.isCancelled else { return }
        if let loaded {
            image = loaded
        } else {
            failed = true
        }
    }
}

/// One thumbnail request, as both of the paths that can end it need to see it.
private struct RequestState: Sendable {
    var id: PHImageRequestID?
    var continuation: CheckedContinuation<NSImage?, Never>?
    var cancelled = false
}

private extension OSAllocatedUnfairLock where State == RequestState {
    /// The continuation if nobody has resumed it yet, leaving none behind.
    func takeContinuation() -> CheckedContinuation<NSImage?, Never>? {
        withLock { state in
            defer { state.continuation = nil }
            return state.continuation
        }
    }
}
