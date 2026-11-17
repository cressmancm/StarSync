import Foundation
import SQLite3
import Testing
@testable import StarSyncCore

/// Reads `Fixtures/tiny.mcat`, a synthetic catalog with the same schema and
/// record shapes as a real Lightroom CC catalog. Regenerate it with
/// `python3 make-fixture.py` in that directory.
@Suite("CatalogReader")
struct CatalogReaderTests {

    static func fixtureCatalog() throws -> LRCatalog {
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mcat", subdirectory: "Fixtures"),
            "tiny.mcat is missing from the test bundle"
        )
        let database = try Database(readOnlyPath: url.path)
        return try CatalogReader.parse(db: database, progress: nil)
    }

    @Test("only real photos are read")
    func assetCount() throws {
        let catalog = try Self.fixtureCatalog()
        // 14 image assets; the deleted row, the deleted_image, the video,
        // the person thumbnail and the preset are all left out.
        #expect(catalog.assets.count == 14)
        #expect(!catalog.assets.contains { $0.fileName == "MOVIE.MOV" })
        #expect(!catalog.assets.contains { $0.fileName == "DSC_0900.NEF" })
        #expect(!catalog.assets.contains { $0.fileName == "DSC_0901.NEF" })
        #expect(!catalog.assets.contains { $0.fileName == "FACE.jpg" })
    }

    @Test("every rating is read correctly")
    func ratings() throws {
        let catalog = try Self.fixtureCatalog()
        let byName = Dictionary(catalog.assets.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })

        #expect(byName["DSC_0000.NEF"]?.rating == 0)
        #expect(byName["DSC_0001.NEF"]?.rating == 1)
        #expect(byName["DSC_0002.NEF"]?.rating == 2)
        #expect(byName["DSC_0003.NEF"]?.rating == 3)
        #expect(byName["DSC_0004.NEF"]?.rating == 4)
        #expect(byName["DSC_0005.NEF"]?.rating == 5)
    }

    @Test("a missing ratings key reads as unrated, not as an error")
    func missingRatingsKey() throws {
        let catalog = try Self.fixtureCatalog()
        let asset = try #require(catalog.assets.first { $0.fileName == "DSC_0006.NEF" })
        #expect(asset.rating == 0)
        #expect(asset.isRated == false)
    }

    @Test("pick and reject flags are read")
    func flags() throws {
        let catalog = try Self.fixtureCatalog()
        let byName = Dictionary(catalog.assets.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byName["DSC_0007.NEF"]?.flag == "pick")
        #expect(byName["DSC_0008.NEF"]?.flag == "reject")
        #expect(byName["DSC_0001.NEF"]?.flag == nil)
    }

    @Test("the rating histogram matches the fixture")
    func histogram() throws {
        let catalog = try Self.fixtureCatalog()
        let histogram = catalog.ratingHistogram
        #expect(histogram[0] == 2)   // DSC_0000 and DSC_0006
        #expect(histogram[1] == 2)   // DSC_0001 and the rejected DSC_0008
        #expect(histogram[2] == 3)   // DSC_0002, DSCF4087 copy, DSC_0013
        #expect(histogram[3] == 2)   // DSC_0003 and DSC_0012
        #expect(histogram[4] == 2)   // DSC_0004 and a DSCF4087
        #expect(histogram[5] == 3)   // DSC_0005, DSC_0007, DSCF3438-Edit
        #expect(catalog.ratedCount == 12)
    }

    @Test("capture dates, dimensions and checksums are read")
    func metadata() throws {
        let catalog = try Self.fixtureCatalog()
        let asset = try #require(catalog.assets.first { $0.fileName == "DSC_0001.NEF" })
        #expect(asset.captureDate == "2026-01-02T03:04:05")
        #expect(asset.pixelWidth == 6240)
        #expect(asset.pixelHeight == 4160)
        #expect(asset.sha256?.count == 64)
    }

    @Test("unusual MessagePack widths decode without disturbing the record")
    func wideTypes() throws {
        let catalog = try Self.fixtureCatalog()
        // DSC_0012 carries uint32, uint16, negative fixint, float64, bool,
        // nil, an array, a binary blob and a str16 alongside its real fields.
        let asset = try #require(catalog.assets.first { $0.fileName == "DSC_0012.NEF" })
        #expect(asset.rating == 3)
        // DSC_0013 has enough keys to force map16 rather than fixmap.
        let wide = try #require(catalog.assets.first { $0.fileName == "DSC_0013.NEF" })
        #expect(wide.rating == 2)
    }

    @Test("albums are read, deleted ones are not")
    func albums() throws {
        let catalog = try Self.fixtureCatalog()
        let names = catalog.albums.map(\.name)
        #expect(names.contains("[26-01] Fixture Album"))
        #expect(names.contains("Empty Album"))
        #expect(names.contains("Fixture Project"))
        #expect(names.contains("Trips"))
        #expect(!names.contains("Deleted Album"))
        #expect(catalog.albums.count == 4)
    }

    @Test("album kinds and parents are read")
    func albumKinds() throws {
        let catalog = try Self.fixtureCatalog()
        let byName = Dictionary(uniqueKeysWithValues: catalog.albums.map { ($0.name, $0) })
        #expect(byName["[26-01] Fixture Album"]?.kind == .collection)
        #expect(byName["Fixture Project"]?.kind == .project)
        #expect(byName["Trips"]?.kind == .collectionSet)
        #expect(byName["[26-01] Fixture Album"]?.parentID == "set1")
        #expect(byName["Empty Album"]?.parentID == nil)
    }

    @Test("album membership is resolved")
    func membership() throws {
        let catalog = try Self.fixtureCatalog()
        let byName = Dictionary(uniqueKeysWithValues: catalog.albums.map { ($0.name, $0) })
        let album = try #require(byName["[26-01] Fixture Album"])
        #expect(album.assetIDs.count == 6)
        #expect(byName["Fixture Project"]?.assetIDs.count == 2)
        #expect(byName["Empty Album"]?.assetIDs.isEmpty == true)

        // Every membership resolves to an asset that was actually read.
        let assets = catalog.assetsByID
        #expect(album.assetIDs.allSatisfy { assets[$0] != nil })
    }

    @Test("albums come back in a stable, readable order")
    func albumOrder() throws {
        let catalog = try Self.fixtureCatalog()
        #expect(catalog.albums.map(\.name) == catalog.albums.map(\.name).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        })
    }

    @Test("a superseded revision is ignored in favour of the winning one")
    func winningRevision() throws {
        // Every fixture doc has an earlier "stale" revision. If the reader
        // followed the wrong one, no file names would come through at all.
        let catalog = try Self.fixtureCatalog()
        #expect(catalog.assets.allSatisfy { !$0.fileName.isEmpty })
    }

    @Test("a library with no catalog inside reports a clear error")
    func missingCatalog() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarSyncTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(throws: CatalogError.self) {
            try CatalogReader.locateCatalog(in: empty)
        }
    }
}

/// A library folder and its database are untrusted input. These build hostile
/// ones at test time, with the SQLite C API, rather than committing them: each
/// is a few lines of SQL and says exactly what it is testing.
@Suite("CatalogReader with untrusted input")
struct CatalogReaderUntrustedInputTests {

    struct SetupError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Builders

    /// A scratch directory for one test. The caller removes it.
    static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarSyncTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The parts of the real schema the reader's query touches.
    static let schema = """
    CREATE TABLE docs(
        localDocId INTEGER PRIMARY KEY,
        fullDocId TEXT,
        winningRevSequence INTEGER,
        deleted BOOLEAN DEFAULT 0,
        type TEXT,
        subtype TEXT);
    CREATE TABLE revs(sequence INTEGER PRIMARY KEY, content BLOB);

    """

    /// MessagePack for `{"importSource": {"fileName": name}}`, as an SQL blob
    /// literal. Names must be under 32 bytes, to stay a fixstr.
    static func record(fileName: String) -> String {
        func string(_ value: String) -> [UInt8] {
            let bytes = Array(value.utf8)
            return [0xa0 | UInt8(bytes.count)] + bytes
        }
        let bytes: [UInt8] = [0x81] + string("importSource") + [0x81] + string("fileName") + string(fileName)
        return "X'" + bytes.map { String(format: "%02X", $0) }.joined() + "'"
    }

    /// SQL inserting one photo as document `number`.
    static func photo(_ number: Int, id: String, fileName: String) -> String {
        """
        INSERT INTO revs VALUES (\(number), \(record(fileName: fileName)));
        INSERT INTO docs(localDocId, fullDocId, winningRevSequence, type, subtype)
            VALUES (\(number), '\(id)', \(number), 'asset', 'image');

        """
    }

    /// Creates a database at `url` holding `sql`. Returns the connection still
    /// open if `keepOpen` is set (the caller closes it), otherwise nil.
    @discardableResult
    static func makeDatabase(at url: URL, _ sql: String, keepOpen: Bool = false) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw SetupError(description: "could not create \(url.path)")
        }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(message)
            sqlite3_close(db)
            throw SetupError(description: text)
        }
        if keepOpen { return db }
        sqlite3_close(db)
        return nil
    }

    /// Lays a library out as Lightroom does, `<name>/<uuid>/Managed Catalog.mcat`,
    /// with `sql` after the schema. Returns the library folder.
    static func makeLibrary(in parent: URL, named name: String = "Test.lrlibrary", _ sql: String) throws -> URL {
        let library = parent.appendingPathComponent(name, isDirectory: true)
        let inner = library.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try makeDatabase(at: inner.appendingPathComponent(CatalogReader.catalogFileName), schema + sql)
        return library
    }

    static func fixtureURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "tiny", withExtension: "mcat", subdirectory: "Fixtures"))
    }

    /// The first column of the first row of `sql`, run on the reader's own
    /// connection.
    static func integer(_ db: Database, _ sql: String) throws -> Int64? {
        try db.withHandle { handle in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SetupError(description: String(cString: sqlite3_errmsg(handle)))
            }
            switch sqlite3_step(statement) {
            case SQLITE_ROW: return sqlite3_column_int64(statement, 0)
            case SQLITE_DONE: return nil
            default: throw SetupError(description: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    // MARK: - What the library folder holds

    @Test("a catalog that is a symlink is refused")
    func symlinkedCatalog() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // A perfectly good database, but reached through a link.
        let elsewhere = dir.appendingPathComponent("elsewhere.mcat")
        try Self.makeDatabase(at: elsewhere, Self.schema + Self.photo(1, id: "a1", fileName: "ONE.NEF"))
        let library = dir.appendingPathComponent("Test.lrlibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: library.appendingPathComponent(CatalogReader.catalogFileName),
            withDestinationURL: elsewhere
        )

        #expect(throws: CatalogError.self) {
            try CatalogReader(libraryURL: library).read()
        }
    }

    @Test("a library reached through a symlinked folder still opens")
    func symlinkedLibraryFolder() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Only the catalog itself must not be a link; the folders above it may
        // be, as /var is on every Mac.
        let real = dir.appendingPathComponent("Pictures", isDirectory: true)
        _ = try Self.makeLibrary(in: real, Self.photo(1, id: "a1", fileName: "ONE.NEF"))
        let alias = dir.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)

        let library = alias.appendingPathComponent("Test.lrlibrary", isDirectory: true)
        let catalog = try CatalogReader(libraryURL: library).read()
        #expect(catalog.assets.map(\.fileName) == ["ONE.NEF"])
    }

    @Test("a folder in place of the catalog is refused")
    func directoryInPlaceOfCatalog() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let library = dir.appendingPathComponent("Test.lrlibrary", isDirectory: true)
        let impostor = library
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(CatalogReader.catalogFileName, isDirectory: true)
        try FileManager.default.createDirectory(at: impostor, withIntermediateDirectories: true)
        try Data("not a catalog".utf8).write(to: impostor.appendingPathComponent("inside.txt"))

        #expect(throws: CatalogError.self) {
            try CatalogReader(libraryURL: library).read()
        }
        // Refused before anything is copied, not merely when SQLite later
        // fails to open a copied folder.
        let root = dir.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(throws: CatalogError.self) {
            try CatalogReader.makeWorkingCopy(of: impostor, in: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("a sidecar that is a symlink is left out of the working copy")
    func symlinkedSidecar() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let library = try Self.makeLibrary(in: dir, Self.photo(1, id: "a1", fileName: "ONE.NEF"))
        let catalogURL = try CatalogReader.locateCatalog(in: library)
        let target = dir.appendingPathComponent("somewhere-else")
        try Data("private".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: URL(fileURLWithPath: catalogURL.path + "-wal"),
            withDestinationURL: target
        )

        let root = dir.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let copy = try CatalogReader.makeWorkingCopy(of: catalogURL, in: root)
        #expect(Self.exists(copy))
        #expect(!Self.exists(URL(fileURLWithPath: copy.path + "-wal")))
    }

    @Test("a path containing ?, #, % and spaces opens correctly")
    func unusualPath() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Each of these means something in a `file:` URI.
        let odd = dir.appendingPathComponent("Odd ?mode=rwc&cache=shared #frag %41%zz", isDirectory: true)
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        let file = odd.appendingPathComponent(CatalogReader.catalogFileName)
        try Self.makeDatabase(at: file, Self.schema + Self.photo(1, id: "a1", fileName: "ONE.NEF"))

        // Opened directly…
        let direct = try CatalogReader.parse(db: Database(readOnlyPath: file.path), progress: nil)
        #expect(direct.assets.map(\.fileName) == ["ONE.NEF"])

        // …as a working copy that itself lives under the odd folder…
        let copy = try CatalogReader.makeWorkingCopy(of: file, in: odd)
        let copied = try CatalogReader.parse(db: Database(readOnlyPath: copy.path), progress: nil)
        #expect(copied.assets.map(\.fileName) == ["ONE.NEF"])

        // …and through the reader, from a library under it.
        let library = try Self.makeLibrary(in: odd, named: "Lib ?#%.lrlibrary", Self.photo(1, id: "a1", fileName: "TWO.NEF"))
        let read = try CatalogReader(libraryURL: library).read()
        #expect(read.assets.map(\.fileName) == ["TWO.NEF"])
    }

    @Test("rows still in the write-ahead log are read")
    func writeAheadLog() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // The tables go into the main file; the photos only into the log.
        let library = try Self.makeLibrary(in: dir, "")
        let catalogURL = try CatalogReader.locateCatalog(in: library)
        // Held open for the whole test, as Lightroom holds its catalog:
        // closing the last connection would checkpoint the log into the file.
        let writer = try Self.makeDatabase(at: catalogURL, """
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            \(Self.photo(1, id: "a1", fileName: "ONE.NEF"))
            \(Self.photo(2, id: "a2", fileName: "TWO.NEF"))
            """, keepOpen: true)
        defer { sqlite3_close(writer) }
        #expect(Self.exists(URL(fileURLWithPath: catalogURL.path + "-wal")))

        let catalog = try CatalogReader(libraryURL: library).read()
        #expect(Set(catalog.assets.map(\.fileName)) == ["ONE.NEF", "TWO.NEF"])

        // The main file holds neither photo, so the read above really did
        // come through the copied -wal.
        let mainFile = try Data(contentsOf: catalogURL)
        #expect(mainFile.range(of: Data("ONE.NEF".utf8)) == nil)
        #expect(mainFile.range(of: Data("TWO.NEF".utf8)) == nil)
    }

    // MARK: - The SQLite connection

    @Test("the connection is hardened before anything is read")
    func hardening() throws {
        let db = try Database(readOnlyPath: Self.fixtureURL().path)

        // Each setting read back from SQLite, not assumed.
        #expect(db.flag(SQLITE_DBCONFIG_TRUSTED_SCHEMA) == false)
        #expect(db.flag(SQLITE_DBCONFIG_DEFENSIVE) == true)
        #expect(try Self.integer(db, "PRAGMA trusted_schema") == 0)
        #expect(try Self.integer(db, "PRAGMA cell_size_check") == 1)
        for limit in Database.limits {
            #expect(db.limit(limit.id) == limit.value)
        }
        #expect(db.limit(SQLITE_LIMIT_LENGTH) == 64 * 1024 * 1024)
        #expect(db.limit(SQLITE_LIMIT_ATTACHED) == 0)

        // No extension loading, no second database, no writes.
        #expect(throws: SetupError.self) { try Self.integer(db, "SELECT load_extension('/tmp/x')") }
        #expect(throws: SetupError.self) { try Self.integer(db, "ATTACH ':memory:' AS other") }
        #expect(throws: SetupError.self) { try Self.integer(db, "CREATE TABLE t(x)") }

        // And the catalog still reads.
        #expect(try CatalogReader.parse(db: db, progress: nil).assets.count == 14)
    }

    /// A view over `docs_t` standing in for `docs`, filtered by `filter`.
    static func catalogWithView(at url: URL, filter: String) throws {
        try makeDatabase(at: url, """
            CREATE TABLE docs_t(
                localDocId INTEGER PRIMARY KEY, fullDocId TEXT, winningRevSequence INTEGER,
                deleted BOOLEAN DEFAULT 0, type TEXT, subtype TEXT);
            CREATE TABLE revs(sequence INTEGER PRIMARY KEY, content BLOB);
            CREATE VIEW docs AS SELECT * FROM docs_t WHERE \(filter);
            INSERT INTO revs VALUES (1, \(record(fileName: "ONE.NEF")));
            INSERT INTO docs_t(localDocId, fullDocId, winningRevSequence, type, subtype)
                VALUES (1, 'a1', 1, 'asset', 'image');
            """)
    }

    @Test("a view in the catalog may not call a function not marked innocuous")
    func untrustedSchema() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Views are still read: real catalogs have not been checked for
        // whether `docs` is always a table.
        let plain = dir.appendingPathComponent("plain.mcat")
        try Self.catalogWithView(at: plain, filter: "1")
        let catalog = try CatalogReader.parse(db: Database(readOnlyPath: plain.path), progress: nil)
        #expect(catalog.assets.map(\.fileName) == ["ONE.NEF"])

        // But one calling an application function is refused, even though the
        // function exists on this connection. With a trusted schema it would run.
        let hostile = dir.appendingPathComponent("hostile.mcat")
        try Self.catalogWithView(at: hostile, filter: "probe() = 1")
        let db = try Database(readOnlyPath: hostile.path)
        let probe: @convention(c) (OpaquePointer?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Void = {
            context, _, _ in sqlite3_result_int(context, 1)
        }
        let registered = db.withHandle {
            sqlite3_create_function_v2($0, "probe", 0, SQLITE_UTF8, nil, probe, nil, nil, nil)
        }
        try #require(registered == SQLITE_OK)

        let error = #expect(throws: CatalogError.self) {
            try CatalogReader.parse(db: db, progress: nil)
        }
        #expect(error?.localizedDescription.contains("unsafe use of probe()") == true)
    }

    @Test("a value over the length limit fails the read rather than being loaded")
    func lengthLimit() throws {
        let db = try Database(readOnlyPath: Self.fixtureURL().path)
        // Stands in for a record larger than the real limit, without writing
        // 64 MB to disk: every fixture record is longer than this.
        db.withHandle { _ = sqlite3_limit($0, SQLITE_LIMIT_LENGTH, 16) }
        #expect(throws: CatalogError.self) {
            try CatalogReader.parse(db: db, progress: nil)
        }
    }

    // MARK: - Working copies

    @Test("stale working copies are removed, recent and unrelated ones are not")
    func staleWorkingCopies() throws {
        let root = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)

        func folder(_ name: String, modified: Date) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("copy".utf8).write(to: url.appendingPathComponent(CatalogReader.catalogFileName))
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            return url
        }
        let stale = try folder("StarSync-\(UUID().uuidString)", modified: twoHoursAgo)
        let recent = try folder("StarSync-\(UUID().uuidString)", modified: now)
        let notOurs = try folder("StarSync-notes", modified: twoHoursAgo)
        let unrelated = try folder("Something", modified: twoHoursAgo)
        // A link named like a working copy is not one; neither it nor what it
        // points at is touched.
        let linkTarget = try folder("target", modified: twoHoursAgo)
        let link = root.appendingPathComponent("StarSync-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: linkTarget)

        CatalogReader.removeStaleWorkingCopies(in: root, olderThan: 60 * 60, now: now)
        #expect(!Self.exists(stale))
        #expect(Self.exists(recent))
        #expect(Self.exists(notOurs))
        #expect(Self.exists(unrelated))
        #expect(Self.exists(link))
        #expect(Self.exists(linkTarget.appendingPathComponent(CatalogReader.catalogFileName)))

        // The threshold is what decides: seen from two hours on, the recent one is stale too.
        CatalogReader.removeStaleWorkingCopies(in: root, olderThan: 60 * 60, now: now.addingTimeInterval(2 * 60 * 60))
        #expect(!Self.exists(recent))
    }

    @Test("making a working copy clears out stale ones and keeps the new one private")
    func workingCopyHousekeeping() throws {
        let root = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        let stale = root.appendingPathComponent("StarSync-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stale, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 60 * 60)], ofItemAtPath: stale.path)

        let copy = try CatalogReader.makeWorkingCopy(of: Self.fixtureURL(), in: root)
        #expect(!Self.exists(stale))
        #expect(Self.exists(copy))

        let scratch = copy.deletingLastPathComponent()
        let permissions = try fm.attributesOfItem(atPath: scratch.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
    }

    @Test("a copy that fails partway leaves no scratch directory behind")
    func failedCopyCleansUp() throws {
        let dir = try Self.scratchDirectory()
        let fm = FileManager.default
        let catalogURL = dir.appendingPathComponent(CatalogReader.catalogFileName)
        try Self.makeDatabase(at: catalogURL, Self.schema)
        // Unreadable, so the copy fails after the scratch directory exists.
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: catalogURL.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: catalogURL.path)
            try? fm.removeItem(at: dir)
        }

        let root = dir.appendingPathComponent("tmp", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(throws: CatalogError.self) {
            try CatalogReader.makeWorkingCopy(of: catalogURL, in: root)
        }
        #expect(try fm.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    // MARK: - What the database holds

    @Test("NULLs and wrongly typed columns are skipped or read as text, never fatal")
    func mistypedColumns() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // No declared types at all, so every value keeps whatever type it was
        // inserted with.
        let file = dir.appendingPathComponent("mistyped.mcat")
        let good = Self.record(fileName: "GOOD.NEF")
        try Self.makeDatabase(at: file, """
            CREATE TABLE docs(localDocId INTEGER PRIMARY KEY, fullDocId, winningRevSequence,
                deleted, type, subtype);
            CREATE TABLE revs(sequence INTEGER PRIMARY KEY, content);
            INSERT INTO revs VALUES (1, \(good));
            INSERT INTO docs VALUES (1, 'a1', 1, 0, 'asset', 'image');
            -- No id, no type: skipped.
            INSERT INTO revs VALUES (2, \(Self.record(fileName: "NOID.NEF")));
            INSERT INTO docs VALUES (2, NULL, 2, 0, 'asset', 'image');
            INSERT INTO revs VALUES (3, \(Self.record(fileName: "NOTYPE.NEF")));
            INSERT INTO docs VALUES (3, 'a3', 3, 0, NULL, 'image');
            -- No content, or empty content: skipped.
            INSERT INTO revs VALUES (4, NULL);
            INSERT INTO docs VALUES (4, 'a4', 4, 0, 'asset', 'image');
            INSERT INTO revs VALUES (5, X'');
            INSERT INTO docs VALUES (5, 'a5', 5, 0, 'asset', 'image');
            -- A subtype that is a number: not "image", so skipped.
            INSERT INTO revs VALUES (6, \(Self.record(fileName: "NUMSUB.NEF")));
            INSERT INTO docs VALUES (6, 'a6', 6, 0, 'asset', 7);
            -- An id that is a number reads as its text.
            INSERT INTO revs VALUES (7, \(Self.record(fileName: "INTID.NEF")));
            INSERT INTO docs VALUES (7, 42, 7, 0, 'asset', 'image');
            -- An id with a NUL inside keeps all of it, rather than becoming "a".
            INSERT INTO revs VALUES (8, \(Self.record(fileName: "NUL.NEF")));
            INSERT INTO docs VALUES (8, X'610062', 8, 0, 'asset', 'image');
            -- A subtype stored as a blob reads as its text.
            INSERT INTO revs VALUES (9, \(Self.record(fileName: "BLOBSUB.NEF")));
            INSERT INTO docs VALUES (9, 'a9', 9, 0, 'asset', X'696D616765');
            -- A winning revision that does not exist: no row.
            INSERT INTO docs VALUES (10, 'a10', 999, 0, 'asset', 'image');
            -- Content stored as text that happens to be a valid record.
            INSERT INTO revs VALUES (11, CAST(\(Self.record(fileName: "TEXT.NEF")) AS TEXT));
            INSERT INTO docs VALUES (11, 'a11', 11, 0, 'asset', 'image');
            """)

        let catalog = try CatalogReader.parse(db: Database(readOnlyPath: file.path), progress: nil)
        let byName = Dictionary(catalog.assets.map { ($0.fileName, $0.id) }, uniquingKeysWith: { first, _ in first })
        #expect(Set(byName.keys) == ["GOOD.NEF", "INTID.NEF", "NUL.NEF", "BLOBSUB.NEF", "TEXT.NEF"])
        #expect(byName["INTID.NEF"] == "42")
        #expect(byName["NUL.NEF"] == "a\u{0}b")
    }

    @Test("a record that is not MessagePack is reported as a damaged catalog", arguments: [
        "'not a record'", "42", "1.5", "X'81'", "X'FF'",
    ])
    func undecodableContent(content: String) throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("bad.mcat")
        try Self.makeDatabase(at: file, Self.schema + """
            INSERT INTO revs VALUES (1, \(content));
            INSERT INTO docs(localDocId, fullDocId, winningRevSequence, type, subtype)
                VALUES (1, 'a1', 1, 'asset', 'image');
            """)
        #expect(throws: CatalogError.self) {
            try CatalogReader.parse(db: Database(readOnlyPath: file.path), progress: nil)
        }
    }

    @Test("a catalog missing a column the query needs is reported, not fatal")
    func missingColumn() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("short.mcat")
        try Self.makeDatabase(at: file, """
            CREATE TABLE docs(localDocId INTEGER PRIMARY KEY, fullDocId TEXT, type TEXT, subtype TEXT);
            CREATE TABLE revs(sequence INTEGER PRIMARY KEY, content BLOB);
            """)
        #expect(throws: CatalogError.self) {
            try CatalogReader.parse(db: Database(readOnlyPath: file.path), progress: nil)
        }
    }

    @Test("a file that is not a database at all is reported, not fatal")
    func notADatabase() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let library = dir.appendingPathComponent("Test.lrlibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: 8192)
            .write(to: library.appendingPathComponent(CatalogReader.catalogFileName))
        #expect(throws: CatalogError.self) {
            try CatalogReader(libraryURL: library).read()
        }
    }

    @Test("a UTF-16 catalog reads the same as a UTF-8 one")
    func utf16Catalog() throws {
        let dir = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("wide.mcat")
        try Self.makeDatabase(at: file, "PRAGMA encoding='UTF-16le';\n" + Self.schema
            + Self.photo(1, id: "a1", fileName: "ONE.NEF"))
        let catalog = try CatalogReader.parse(db: Database(readOnlyPath: file.path), progress: nil)
        #expect(catalog.assets.map(\.id) == ["a1"])
        #expect(catalog.assets.map(\.fileName) == ["ONE.NEF"])
    }
}
