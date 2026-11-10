import Foundation
import Photos
import StarSyncCore

/// Reads the Apple Photos library through PhotoKit.
///
/// macOS 27 is the first release with a real star rating on `PHAsset`, which
/// is why StarSync requires it. AppleScript still has no rating property, so
/// PhotoKit is the only way to do this at all.
enum PhotosLibrary {

    enum AccessError: LocalizedError {
        case denied
        case limited

        var errorDescription: String? {
            switch self {
            case .denied:
                return "StarSync needs access to your Photos library."
            case .limited:
                return "StarSync has access to only some of your photos."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .denied:
                return "Open System Settings › Privacy & Security › Photos and turn on Full Access for StarSync."
            case .limited:
                return "StarSync has to see your whole library to match it against Lightroom. Open System Settings › Privacy & Security › Photos and change StarSync to Full Access."
            }
        }
    }

    /// Asks for read-write access, which is what writing a rating needs.
    static func requestAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized: return
        case .limited: throw AccessError.limited
        default: throw AccessError.denied
        }
    }

    static var currentStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Every photo in the library, flattened into `StarSyncCore.PhotoAsset`.
    ///
    /// `prefetchAssetExtendedMetadata` pulls the original file names in one
    /// pass; without it PhotoKit fetches them one asset at a time, which on a
    /// library this size takes minutes rather than seconds.
    static func fetchPhotos(progress: (@Sendable (Int) -> Void)? = nil) -> PhotosSnapshot {
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: options)
        var photos: [PhotoAsset] = []
        photos.reserveCapacity(result.count)
        var namesFromResources = 0

        result.enumerateObjects { asset, index, _ in
            var filename = asset.extendedMetadata.originalFilename
            if filename == nil || filename?.isEmpty == true {
                // Older imports may carry no extended metadata. The resource
                // list is slower, so it is only consulted when needed.
                filename = PHAssetResource.assetResources(for: asset)
                    .first(where: { $0.type == .photo })?.filename
                if filename != nil { namesFromResources += 1 }
            }

            photos.append(
                PhotoAsset(
                    id: asset.localIdentifier,
                    originalFilename: filename,
                    creationDate: asset.creationDate,
                    rating: asset.rating.rawValue,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isEditable: asset.canPerform(.properties)
                )
            )
            if index % 500 == 0 { progress?(index) }
        }

        return PhotosSnapshot(photos: photos, namesFromResources: namesFromResources)
    }

    /// Looks up live `PHAsset`s by local identifier, for writing or for
    /// loading a thumbnail. Assets are refetched rather than held, so a change
    /// made in Photos.app meanwhile cannot leave StarSync writing to a stale
    /// object.
    /// The current rating of a specific set of photos.
    ///
    /// After a sync only a few hundred photos have changed, so this refetches
    /// just those. Refetching the whole library to learn them would mean
    /// enumerating tens of thousands of assets for no reason.
    static func ratings(for identifiers: [String]) -> [String: Int] {
        assets(withIdentifiers: identifiers).mapValues { $0.rating.rawValue }
    }

    static func assets(withIdentifiers identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            assets[asset.localIdentifier] = asset
        }
        return assets
    }
}

struct PhotosSnapshot: Sendable {
    var photos: [PhotoAsset]
    /// How many file names had to come from the resource list rather than
    /// from extended metadata. Surfaced so a library that reports none can be
    /// recognized rather than silently failing to match.
    let namesFromResources: Int

    var ratingHistogram: [Int: Int] {
        var histogram: [Int: Int] = [:]
        for photo in photos { histogram[photo.rating, default: 0] += 1 }
        return histogram
    }

    var withoutFilename: Int {
        photos.count { $0.originalFilename?.isEmpty ?? true }
    }

    /// Folds freshly written ratings back in, leaving every other photo as it was.
    mutating func apply(ratings: [String: Int]) {
        guard !ratings.isEmpty else { return }
        photos = photos.map { photo in
            guard let rating = ratings[photo.id], rating != photo.rating else { return photo }
            return photo.withRating(rating)
        }
    }
}
