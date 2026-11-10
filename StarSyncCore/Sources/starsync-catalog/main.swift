import Foundation
import StarSyncCore

// A small development tool: reads a Lightroom catalog and prints what
// StarSyncCore found. Used to check the reader against a real catalog
// without involving the Photos library or the app.

let arguments = Array(CommandLine.arguments.dropFirst())
let defaultLibrary = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Pictures/Lightroom Library.lrlibrary")

let libraryURL = arguments.first.map { URL(fileURLWithPath: $0) } ?? defaultLibrary
let showAlbums = arguments.contains("--albums")

guard FileManager.default.fileExists(atPath: libraryURL.path) else {
    FileHandle.standardError.write(Data("No Lightroom library at \(libraryURL.path)\n".utf8))
    exit(1)
}

do {
    let started = Date()
    let catalog = try CatalogReader(libraryURL: libraryURL).read { step in
        FileHandle.standardError.write(Data("  \(step)\n".utf8))
    }
    let elapsed = Date().timeIntervalSince(started)

    let histogram = catalog.ratingHistogram
    print("")
    print("Catalog: \(libraryURL.path)")
    print(String(format: "Read in %.1fs", elapsed))
    print("")
    print("Photos:          \(catalog.assets.count)")
    for stars in 1...5 {
        print("  \(String(repeating: "★", count: stars))\(String(repeating: " ", count: 5 - stars))        \(histogram[stars] ?? 0)")
    }
    print("  unrated        \(histogram[0] ?? 0)")
    print("  rated (1★+)    \(catalog.ratedCount)")
    print("")

    let byKind = Dictionary(grouping: catalog.albums, by: \.kind)
    print("Albums:")
    for kind in [LRAlbum.Kind.collection, .project, .collectionSet, .other] {
        if let albums = byKind[kind] { print("  \(kind.rawValue)   \(albums.count)") }
    }
    let memberships = catalog.albums.reduce(0) { $0 + $1.assetIDs.count }
    print("  memberships     \(memberships)")

    let missingName = catalog.assets.count { $0.fileName.isEmpty }
    if missingName > 0 { print("\nWarning: \(missingName) photos had no file name.") }

    if showAlbums {
        print("")
        for album in catalog.albums where album.kind == .collection {
            let rated = album.assetIDs.compactMap { catalog.assetsByID[$0] }.count(where: \.isRated)
            print("  \(album.name)  —  \(album.assetIDs.count) photos, \(rated) rated")
        }
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
