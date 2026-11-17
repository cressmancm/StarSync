import Foundation
import SQLite3
import CSQLiteShim

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

    /// Names every working-copy directory, so a later read can recognise
    /// leftovers as its own.
    static let workingCopyPrefix = "StarSync-"

    /// How long a working copy must have gone untouched before a later read
    /// treats it as abandoned. A read takes seconds to a few minutes, so an
    /// hour never disturbs one still running in another process.
    static let staleWorkingCopyAge: TimeInterval = 60 * 60

    /// Copies the catalog and its WAL sidecars into a temporary directory.
    ///
    /// `root` is the system temporary directory except in tests.
    static func makeWorkingCopy(
        of catalogURL: URL,
        in root: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let fm = FileManager.default
        removeStaleWorkingCopies(in: root)

        // The library folder is untrusted. `copyItem` copies a symlink as a
        // symlink (which SQLite would then follow, outside the copy) and a
        // directory recursively, so only a plain file is accepted. The check
        // is on the catalog itself, never on the folders above it: a library
        // reached through a symlinked folder is fine.
        guard isRegularFile(catalogURL) else {
            throw CatalogError.copyFailed("“\(catalogURL.lastPathComponent)” is a link or a folder, not a catalog file.")
        }

        // 0700: the copy is the user's whole photo library's metadata.
        let scratch = root
            .appendingPathComponent("\(workingCopyPrefix)\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(
                at: scratch,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw CatalogError.copyFailed(error.localizedDescription)
        }

        // From here on a failure must not strand a partial copy of the catalog
        // in the temporary directory.
        do {
            let destination = scratch.appendingPathComponent(catalogURL.lastPathComponent)
            try fm.copyItem(at: catalogURL, to: destination)
            // The catalog can be swapped between the check above and the copy;
            // checking what actually arrived closes that gap.
            guard isRegularFile(destination) else {
                throw CatalogError.copyFailed("“\(catalogURL.lastPathComponent)” changed while it was being copied.")
            }

            // -wal and -shm may legitimately be absent when Lightroom is closed
            // and the log has been checkpointed. One that is not a plain file
            // is ignored, as if absent, for the same reason as the catalog.
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: catalogURL.path + suffix)
                guard isRegularFile(sidecar) else { continue }
                try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: destination.path + suffix))
            }
            return destination
        } catch {
            try? fm.removeItem(at: scratch)
            throw (error as? CatalogError) ?? CatalogError.copyFailed(error.localizedDescription)
        }
    }

    /// Removes working copies that a crashed or force-quit read never got to
    /// clean up. Each holds a copy of the user's whole catalog, and nothing
    /// else would ever delete it.
    ///
    /// Only directories named exactly as `makeWorkingCopy` names them, and
    /// untouched for `age`, are removed. Failures are ignored: this is
    /// housekeeping and must never stop a read.
    static func removeStaleWorkingCopies(
        in root: URL,
        olderThan age: TimeInterval = staleWorkingCopyAge,
        now: Date = Date()
    ) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else {
            return
        }
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix(workingCopyPrefix),
                  UUID(uuidString: String(name.dropFirst(workingCopyPrefix.count))) != nil,
                  let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) > age
            else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    /// True only if `url` is itself a regular file. `attributesOfItem` reports
    /// on a symlink rather than what it points to, so a link is never followed.
    static func isRegularFile(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeRegular
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
                let record = try decoding(id) { try MessagePack.decodeMap(blob, skippingKeys: skippedAssetKeys) }
                assets.append(makeAsset(id: id, record: record))

            case "album":
                let record = try decoding(id) { try MessagePack.decodeMap(blob) }
                guard let name = record.string("name") else { return }
                albumsByID[id] = LRAlbum(
                    id: id,
                    name: name,
                    kind: LRAlbum.Kind(rawValue: subtype ?? "") ?? .other,
                    parentID: record.string("parent.id")
                )

            case "album_asset":
                let record = try decoding(id) { try MessagePack.decodeMap(blob) }
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

    /// Decodes one record, reporting a malformed one as a damaged catalog:
    /// callers handle CatalogError, not the decoder's own error type.
    static func decoding<T>(_ id: String, _ decode: () throws -> T) throws -> T {
        do {
            return try decode()
        } catch {
            // The id comes from the file, so only a bounded piece of it is quoted.
            throw CatalogError.queryFailed("record “\(id.prefix(80))” could not be decoded (\(error))")
        }
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

    /// Run-time limits for this connection, set before anything is read.
    ///
    /// SQLite's defaults suit applications that build arbitrary SQL; this one
    /// runs a single fixed query over a file it does not trust. Several of
    /// these also govern the file's own schema (statement length, expression
    /// depth, compound selects, function arguments), so they are set far above
    /// anything a real schema needs rather than tight. The column limit is
    /// left at its default for the same reason: a Lightroom table wider than a
    /// guess would make a real catalog unreadable.
    static let limits: [(id: Int32, value: Int32)] = [
        // A real record is a few kilobytes. A larger value fails the read with
        // SQLITE_TOOBIG instead of being copied into memory.
        (SQLITE_LIMIT_LENGTH, 64 * 1024 * 1024),
        (SQLITE_LIMIT_SQL_LENGTH, 1_000_000),
        (SQLITE_LIMIT_EXPR_DEPTH, 100),
        (SQLITE_LIMIT_COMPOUND_SELECT, 20),
        (SQLITE_LIMIT_VDBE_OP, 100_000),
        (SQLITE_LIMIT_FUNCTION_ARG, 32),
        // Nothing here attaches another database, so nothing may.
        (SQLITE_LIMIT_ATTACHED, 0),
        (SQLITE_LIMIT_LIKE_PATTERN_LENGTH, 1_000),
        (SQLITE_LIMIT_VARIABLE_NUMBER, 16),
    ]

    init(readOnlyPath path: String) throws {
        // A plain path, not a `file:` URI: the path is not percent-encoded,
        // so a `?`, `#` or `%` in it would be read as URI syntax and could
        // smuggle in parameters. The system SQLite is built with
        // SQLITE_USE_URI, which treats any name starting `file:` as a URI even
        // without SQLITE_OPEN_URI; an absolute path can never start that way.
        guard path.hasPrefix("/") else {
            throw CatalogError.cannotOpen("“\(path)” is not an absolute path.")
        }
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            close()
            throw CatalogError.cannotOpen(message)
        }
        do {
            try harden()
        } catch {
            close()
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    /// Closes the connection early, on a failed init.
    ///
    /// `handle` is cleared because deinit still runs when init throws (every
    /// stored property is initialised by then), and closing the same handle
    /// twice is a use-after-free.
    private func close() {
        sqlite3_close(handle)
        handle = nil
    }

    /// Locks the connection down before the file's schema is first read.
    /// SQLite loads the schema lazily, on the first statement, so everything
    /// here is in force by the time anything from the file is parsed.
    private func harden() throws {
        // Views, triggers, CHECK constraints, defaults, indexes and generated
        // columns all come from the file. With the schema untrusted they may
        // only call functions marked innocuous and may not use virtual tables.
        // Views themselves stay usable: real catalogs have not been checked
        // for whether `docs` and `revs` are always plain tables.
        try setFlag(SQLITE_DBCONFIG_TRUSTED_SCHEMA, to: false)
        // Turns off the features that let SQL deliberately corrupt a database
        // (writable_schema, sqlite_dbpage writes and the like). The connection
        // is read-only and runs only StarSync's own SQL, so this is a backstop.
        try setFlag(SQLITE_DBCONFIG_DEFENSIVE, to: true)
        // Extension loading needs no switch: the system SQLite is built
        // without it (SQLITE_OMIT_LOAD_EXTENSION), so there is no
        // load_extension() for the schema to reach and the
        // SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION option is rejected outright.
        // A test checks that load_extension() stays absent.

        for limit in Self.limits {
            sqlite3_limit(handle, limit.id, limit.value)
        }

        // Checks every b-tree cell's size against its page as it is read, so
        // a corrupt page is reported as SQLITE_CORRUPT rather than read past.
        guard sqlite3_exec(handle, "PRAGMA cell_size_check=ON", nil, nil, nil) == SQLITE_OK else {
            throw CatalogError.cannotOpen(String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// Sets an on/off `SQLITE_DBCONFIG_` option and checks that it took.
    private func setFlag(_ option: Int32, to enabled: Bool) throws {
        var current: Int32 = -1
        let status = starsync_sqlite3_db_config_int(handle, option, enabled ? 1 : 0, &current)
        guard status == SQLITE_OK, (current != 0) == enabled else {
            throw CatalogError.cannotOpen("SQLite refused a safety setting (option \(option)).")
        }
    }

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
            // A row with no id or type cannot be placed; skip it rather than
            // fail the whole catalog.
            guard let id = try text(statement, 0),
                  let type = try text(statement, 1)
            else { continue }
            let subtype = try text(statement, 2)

            let blob = try blob(statement, 3)
            guard !blob.isEmpty else { continue }
            try row(id, type, subtype, blob)
        }
    }

    /// Column `index` as text, or nil if it is NULL.
    ///
    /// SQLite converts a column of any other type, so a mistyped value reads
    /// as text rather than failing. The bytes are taken by the length that
    /// `sqlite3_column_bytes` reports after `sqlite3_column_text` (the order
    /// the SQLite docs require), not up to the first NUL: an id with a NUL
    /// inside stays itself instead of being cut down to some other document's
    /// id. Invalid UTF-8 is repaired rather than trusted.
    private func text(_ statement: OpaquePointer?, _ index: Int32) throws -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let pointer = sqlite3_column_text(statement, index) else {
            try checkOutOfMemory()
            return ""
        }
        let length = Int(sqlite3_column_bytes(statement, index))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self)
    }

    /// Column `index` as bytes; empty if it is NULL or empty.
    ///
    /// `sqlite3_column_blob` is called before `sqlite3_column_bytes`, the
    /// order the SQLite docs require, so the length describes the bytes the
    /// pointer actually points at.
    private func blob(_ statement: OpaquePointer?, _ index: Int32) throws -> Data {
        guard let pointer = sqlite3_column_blob(statement, index) else {
            try checkOutOfMemory()
            return Data()
        }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }

    /// A column accessor returns NULL both for an empty value and when SQLite
    /// ran out of memory converting it. Only the second is an error.
    private func checkOutOfMemory() throws {
        if sqlite3_errcode(handle) == SQLITE_NOMEM {
            throw CatalogError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    // MARK: Inspection, for the tests that check the hardening took effect

    /// The current state of an on/off `SQLITE_DBCONFIG_` option.
    func flag(_ option: Int32) -> Bool? {
        var current: Int32 = -1
        guard starsync_sqlite3_db_config_int(handle, option, -1, &current) == SQLITE_OK else { return nil }
        return current != 0
    }

    /// The current value of a run-time limit.
    func limit(_ id: Int32) -> Int32 {
        sqlite3_limit(handle, id, -1)
    }

    /// The raw connection, for tests that need to go beyond `query`.
    func withHandle<T>(_ body: (OpaquePointer?) throws -> T) rethrows -> T {
        try body(handle)
    }
}
