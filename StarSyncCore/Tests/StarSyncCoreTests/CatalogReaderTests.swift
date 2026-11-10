import Foundation
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
