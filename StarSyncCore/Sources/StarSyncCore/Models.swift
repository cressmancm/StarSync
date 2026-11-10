import Foundation

/// A photo in the Lightroom catalog.
public struct LRAsset: Sendable, Identifiable, Equatable {
    /// Lightroom's `fullDocId` for the asset.
    public let id: String
    /// Original file name as imported, e.g. `DSCF4087.RAF`.
    public let fileName: String
    /// Capture time as Lightroom records it: wall-clock local time with no zone.
    public let captureDate: String?
    /// Star rating, 0–5. Zero means "not triaged yet", never "zero stars".
    public let rating: Int
    /// `pick` or `reject`, read for display only; StarSync never writes flags.
    public let flag: String?
    public let sha256: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public init(
        id: String,
        fileName: String,
        captureDate: String? = nil,
        rating: Int = 0,
        flag: String? = nil,
        sha256: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.captureDate = captureDate
        self.rating = rating
        self.flag = flag
        self.sha256 = sha256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// File name without its extension, lowercased: the primary match key.
    public var stem: String { FilenameMatching.stem(of: fileName) }

    /// True when Lightroom has an actual rating to contribute.
    public var isRated: Bool { rating > 0 }
}

/// An album, collection or project in the Lightroom catalog.
public struct LRAlbum: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable {
        case collection
        case project
        case collectionSet = "collection_set"
        case other
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let parentID: String?
    /// `fullDocId`s of the assets in this album.
    public var assetIDs: [String]

    public init(id: String, name: String, kind: Kind, parentID: String? = nil, assetIDs: [String] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentID = parentID
        self.assetIDs = assetIDs
    }
}

/// Everything StarSync needs from a Lightroom catalog.
public struct LRCatalog: Sendable {
    public let assets: [LRAsset]
    public let albums: [LRAlbum]

    public init(assets: [LRAsset], albums: [LRAlbum]) {
        self.assets = assets
        self.albums = albums
    }

    public var assetsByID: [String: LRAsset] {
        Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Count of assets at each rating 0–5.
    public var ratingHistogram: [Int: Int] {
        var histogram = [Int: Int]()
        for asset in assets { histogram[asset.rating, default: 0] += 1 }
        return histogram
    }

    public var ratedCount: Int { assets.count(where: \.isRated) }
}

/// A photo in the Apple Photos library, flattened so that `StarSyncCore`
/// never has to import PhotoKit and stays testable without a photo library.
public struct PhotoAsset: Sendable, Identifiable, Equatable {
    /// `PHAsset.localIdentifier`.
    public let id: String
    /// `PHAsset.extendedMetadata.originalFilename`, or the resource filename.
    public let originalFilename: String?
    /// `PHAsset.creationDate`.
    public let creationDate: Date?
    /// `PHAsset.rating` as 0–5, where 0 is `.unset`.
    public let rating: Int
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    /// `PHAsset.canPerformEditOperation(.properties)` — false for assets
    /// StarSync is not allowed to change, such as items from a shared library.
    public let isEditable: Bool

    public init(
        id: String,
        originalFilename: String?,
        creationDate: Date?,
        rating: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        isEditable: Bool = true
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.creationDate = creationDate
        self.rating = rating
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isEditable = isEditable
    }

    public var stem: String? {
        originalFilename.map { FilenameMatching.stem(of: $0) }
    }

    /// The same photo with a different rating.
    ///
    /// Used to fold a freshly written rating back into the in-memory
    /// snapshot, so a second pass compares against what is really in Photos
    /// without refetching the library.
    public func withRating(_ newRating: Int) -> PhotoAsset {
        PhotoAsset(
            id: id,
            originalFilename: originalFilename,
            creationDate: creationDate,
            rating: newRating,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isEditable: isEditable
        )
    }
}

// MARK: - Filename handling

public enum FilenameMatching {
    /// Lowercased file name with its extension removed.
    public static func stem(of fileName: String) -> String {
        let name = (fileName as NSString).lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return name.lowercased()
        }
        return String(name[name.startIndex..<dot]).lowercased()
    }

    /// Suffixes Lightroom and Photos append to derived files.
    static let derivedSuffixes = ["-edit", "-enhanced-nr", "-enhanced", "-hdr", "-pano", " copy", "-copy"]

    /// Strips one trailing derived-file or duplicate marker, if present.
    ///
    /// `dscf3438-edit` → `dscf3438`, `nz8_5779-2` → `nz8_5779`.
    /// Returns nil when there is nothing to strip, so callers can tell a
    /// second pass apart from a repeat of the first.
    public static func strippingDerivedSuffix(_ stem: String) -> String? {
        for suffix in derivedSuffixes where stem.hasSuffix(suffix) {
            let trimmed = String(stem.dropLast(suffix.count))
            if !trimmed.isEmpty { return trimmed }
        }
        // Trailing duplicate counters: -2, _3, and so on. Only strip a short
        // run of digits, so DSCF4087 keeps its number.
        if let dash = stem.lastIndex(where: { $0 == "-" || $0 == "_" }) {
            let tail = stem[stem.index(after: dash)...]
            if tail.count <= 2, !tail.isEmpty, tail.allSatisfy(\.isNumber) {
                let trimmed = String(stem[stem.startIndex..<dash])
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
