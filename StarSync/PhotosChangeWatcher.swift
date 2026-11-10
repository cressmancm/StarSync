import Foundation
import Photos

/// Notices when the Photos library changes while StarSync is looking at it.
///
/// A preview is built from a snapshot, and someone can rate a photo in
/// Photos.app the moment after it is drawn. The write path already guards
/// against acting on a stale comparison, but that only makes the outcome safe
/// — it does not make the screen honest. This exists so a stale preview can
/// say so and offer to rebuild itself.
///
/// It deliberately reports nothing about *what* changed. `PHChange` can say,
/// but acting on it would mean re-planning rows under the person's cursor
/// while they are reading them. A flag and a button leave them in charge.
final class PhotosChangeWatcher: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @MainActor @Sendable () -> Void

    init(onChange: @MainActor @Sendable @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// Called by PhotoKit on an arbitrary queue.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        let notify = onChange
        Task { @MainActor in notify() }
    }
}
