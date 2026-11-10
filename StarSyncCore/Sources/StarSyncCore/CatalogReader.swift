import Foundation
import SQLite3

public enum CatalogError: Error, LocalizedError {
    case noCatalogFound(URL)
    case cannotOpen(String)
    case queryFailed(String)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noCatalogFound(let url):
            return "No Lightroom catalog found inside \(url.lastPathComponent). Expected a folder containing “Managed Catalog.mcat”."
        case .cannotOpen(let message):
            return "Could not open the Lightroom catalog: \(message)"
        case .queryFailed(let message):
            return "Could not read the Lightroom catalog: \(message)"
        case .copyFailed(let message):
            return "Could not make a working copy of the Lightroom catalog: \(message)"
        }
    }
}

/// Reads a Lightroom CC catalog (`.lrlibrary`).
///
/// The catalog is opened strictly read-only, and from a temporary copy rather
/// than in place: Lightroom may be running and holding the write-ahead log,
/// and a read-only handle on the original cannot create the shared-memory file
/// it would need to see those pages. StarSync never writes to a catalog.
public struct CatalogReader: Sendable {
    public static let catalogFileName = "Managed Catalog.mcat"

    private let libraryURL: URL

    public init(libraryURL: URL) {
        self.libraryURL = libraryURL
    }

    /// Finds the catalog database inside an `.lrlibrary` bundle.
    ///
    /// The containing folder is named with a per-install UUID, so it is
    /// discovered rather than assumed.
    public static func locateCatalog(in libraryURL: URL) throws -> URL {
        let direct = libraryURL.appendingPathComponent(catalogFileName)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in children {
            let candidate = child.appendingPathComponent(catalogFileName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw CatalogError.noCatalogFound(libraryURL)
    }

    /// Reads every asset and album from the catalog.
    public func read(progress: (@Sendable (String) -> Void)? = nil) throws -> LRCatalog {
        let catalogURL = try Self.locateCatalog(in: libraryURL)

        progress?("Copying catalog…")
        let workingCopy = try Self.makeWorkingCopy(of: catalogURL)
        defer { try? FileManager.default.removeItem(at: workingCopy.deletingLastPathComponent()) }

        progress?("Opening catalog…")
        let db = try Database(readOnlyPath: workingCopy.path)

        progress?("Reading photos…")
        return try Self.parse(db: db, progress: progress)
    }

    // MARK: - Working copy

    /// Copies the catalog and its WAL sidecars into a temporary directory.
    static func makeWorkingCopy(of catalogURL: URL) throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("StarSync-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            throw CatalogError.copyFailed(error.localizedDescription)
        }

        let destination = scratch.appendingPathComponent(catalogURL.lastPathComponent)
        do {
            try fm.copyItem(at: catalogURL, to: destination)
        } catch {
            throw CatalogError.copyFailed(error.localizedDescription)
        }

        // -wal and -shm may legitimately be absent when Lightroom is closed
        // and the log has been checkpointed.
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: catalogURL.path + suffix)
            guard fm.fileExists(atPath: sidecar.path) else { continue }
            try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: destination.path + suffix))
        }
        return destination
    }

    // MARK: - Parsing

    /// Top-level keys skipped while decoding an asset.
    ///
    /// `develop` carries several kilobytes of Camera Raw XMP per photo and
    /// nothing here needs it.
    static let skippedAssetKeys: Set<String> = ["develop", "aesthetics", "autoTags", "importedByVersion"]

    static func parse(db: Database, progress: (@Sendable (String) -> Void)?) throws -> LRCatalog {
        var assets: [LRAsset] = []
        var albumsByID: [String: LRAlbum] = [:]
        var membership: [(album: String, asset: String)] = []

        let sql = """
        SELECT d.fullDocId, d.type, d.subtype, r.content
        FROM docs d JOIN revs r ON r.sequence = d.winningRevSequence
        WHERE d.deleted = 0 AND d.type IN ('asset', 'album', 'album_asset')
        """

        try db.query(sql) { id, type, subtype, blob in
            switch type {
            case "asset":
                // Only real photos: skips `person`, `preset`, `stack`, `task`,
                // `video` and the `deleted_image` tombstones.
                guard subtype == "image" else { return }
                let record = try MessagePack.decodeMap(blob, skippingKeys: skippedAssetKeys)
                assets.append(makeAsset(id: id, record: record))

            case "album":
                let record = try MessagePack.decodeMap(blob)
                guard let name = record.string("name") else { return }
                albumsByID[id] = LRAlbum(
                    id: id,
                    name: name,
                    kind: LRAlbum.Kind(rawValue: subtype ?? "") ?? .other,
                    parentID: record.string("parent.id")
                )

            case "album_asset":
                let record = try MessagePack.decodeMap(blob)
                if let album = record.string("album.id"), let asset = record.string("asset.id") {
                    membership.append((album, asset))
                }

            default:
                return
            }
        }

        for link in membership {
            albumsByID[link.album]?.assetIDs.append(link.asset)
        }

        let albums = albumsByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return LRCatalog(assets: assets, albums: albums)
    }

    static func makeAsset(id: String, record: [String: MPValue]) -> LRAsset {
        // Ratings and review flags are keyed by Lightroom account id. A
        // catalog normally has one, but take the highest rating present so a
        // shared catalog still reads sensibly, and never hardcode an account.
        var rating = 0
        if let ratings = record["ratings"]?.mapValue {
            for entry in ratings.values {
                if let value = entry["rating"]?.intValue { rating = max(rating, value) }
            }
        }
        var flag: String?
        if let reviews = record["reviews"]?.mapValue {
            for entry in reviews.values {
                if let value = entry["flag"]?.stringValue { flag = value }
            }
        }

        return LRAsset(
            id: id,
            fileName: record.string("importSource.fileName") ?? "",
            captureDate: record.string("captureDate"),
            rating: min(max(rating, 0), 5),
            flag: flag,
            sha256: record.string("importSource.sha256"),
            pixelWidth: record.int("importSource.originalWidth"),
            pixelHeight: record.int("importSource.originalHeight")
        )
    }
}

// MARK: - Minimal read-only SQLite wrapper

/// A read-only SQLite handle. Deliberately tiny: StarSync only ever runs one
/// query, and this avoids taking on a dependency.
final class Database {
    private var handle: OpaquePointer?

    init(readOnlyPath path: String) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let uri = "file:\(path)?mode=ro"
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw CatalogError.cannotOpen(message)
        }
    }

    deinit { sqlite3_close(handle) }

    /// Runs `sql`, handing each row to `row` as (fullDocId, type, subtype, content).
    ///
    /// `content` is read with `sqlite3_column_blob`, never as text: the
    /// MessagePack payload is not valid UTF-8 and a text read mangles it.
    func query(
        _ sql: String,
        row: (String, String, String?, Data) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw CatalogError.queryFailed(String(cString: sqlite3_errmsg(handle)))
            }
            guard let idText = sqlite3_column_text(statement, 0),
                  let typeText = sqlite3_column_text(statement, 1)
            else { continue }

            let id = String(cString: idText)
            let type = String(cString: typeText)
            let subtype = sqlite3_column_text(statement, 2).map { String(cString: $0) }

            let length = Int(sqlite3_column_bytes(statement, 3))
            let blob: Data
            if length > 0, let pointer = sqlite3_column_blob(statement, 3) {
                blob = Data(bytes: pointer, count: length)
            } else {
                blob = Data()
            }
            guard !blob.isEmpty else { continue }
            try row(id, type, subtype, blob)
        }
    }
}
