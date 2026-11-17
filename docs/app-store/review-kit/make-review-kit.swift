// Builds the StarSync Review Kit: eight photos and a Lightroom library that
// rates them, so someone with no Lightroom can see the app do its job.
//
//     swift docs/app-store/review-kit/make-review-kit.swift
//
// Writes build/StarSync Review Kit.zip (build/ is gitignored). Attach it to
// the App Review Information section in App Store Connect.
//
// App Review will not have Lightroom, and without a library StarSync stops at
// its first screen — which is the shape of a guideline 2.1 rejection. A
// Lightroom CC library turns out to be nothing more than a folder holding
// `Managed Catalog.mcat`, a SQLite database of MessagePack records, so one
// can be written from scratch. The records here have the same shape as the
// test fixture's (StarSyncCore/Tests/.../make-fixture.py), minus everything
// that exists there only to exercise the reader's edge cases.

import AppKit
import ImageIO
import SQLite3
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let build = root.appendingPathComponent("build")
let kit = build.appendingPathComponent("review-kit/StarSync Review Kit")
let photosDir = kit.appendingPathComponent("Demo Photos")
let library = kit.appendingPathComponent("Demo Library.lrlibrary")
let zip = build.appendingPathComponent("StarSync Review Kit.zip")

let fm = FileManager.default
try? fm.removeItem(at: kit)
try? fm.removeItem(at: zip)
try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
try fm.createDirectory(at: library, withIntermediateDirectories: true)

// MARK: - The photos

struct Demo {
    let number: Int
    let rating: Int
    let flag: String?
    let colors: (UInt32, UInt32)

    var fileName: String { String(format: "DEMO_%04d.jpg", number) }
    var id: String { String(format: "demo%04d", number) }
    // A day apart, so no two could be confused even if the names were.
    var capture: String { String(format: "2026-03-%02dT10:00:00", number) }
    var exifDate: String { String(format: "2026:03:%02d 10:00:00", number) }
}

// Every rating from one to five, one photo Lightroom leaves at zero — which
// StarSync must leave alone — and two fives, so the album holding only the
// best has more than one photo in it.
let demos = [
    Demo(number: 1, rating: 5, flag: "pick", colors: (0xF2A65A, 0x8E3B46)),
    Demo(number: 2, rating: 4, flag: nil,    colors: (0x5B8DEF, 0x1F2D5C)),
    Demo(number: 3, rating: 3, flag: nil,    colors: (0x6CC5A0, 0x1E4D40)),
    Demo(number: 4, rating: 5, flag: "pick", colors: (0xE86A92, 0x3E1F47)),
    Demo(number: 5, rating: 2, flag: nil,    colors: (0xF6D365, 0xA0522D)),
    Demo(number: 6, rating: 1, flag: nil,    colors: (0x9AA5B1, 0x323F4B)),
    Demo(number: 7, rating: 0, flag: nil,    colors: (0xB794F4, 0x44337A)),
    Demo(number: 8, rating: 4, flag: nil,    colors: (0x63B3ED, 0x2C5282)),
]

let width = 1800, height = 1200

func cg(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

for demo in demos {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let gradient = CGGradient(colorsSpace: space,
                              colors: [cg(demo.colors.0), cg(demo.colors.1)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)),
                           end: CGPoint(x: CGFloat(width), y: 0), options: [])

    // The file name, large, so a reviewer can tell in Photos which is which
    // without opening the Info panel. Deliberately not the rating: that has
    // to come from the library, and a star drawn on the picture would make
    // it impossible to tell whether StarSync wrote anything.
    let label = NSAttributedString(string: demo.fileName, attributes: [
        .font: NSFont.systemFont(ofSize: 140, weight: .semibold),
        .foregroundColor: NSColor(white: 1, alpha: 0.92),
    ])
    let line = CTLineCreateWithAttributedString(label)
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (CGFloat(width) - b.width) / 2 - b.minX,
                               y: (CGFloat(height) - b.height) / 2 - b.minY)
    CTLineDraw(line, ctx)

    let url = photosDir.appendingPathComponent(demo.fileName)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    // The capture date goes in EXIF, which is where Photos takes a photo's
    // date from on import, so it lines up with `captureDate` in the catalog.
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.85,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: demo.exifDate,
            kCGImagePropertyExifDateTimeDigitized: demo.exifDate,
        ],
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFDateTime: demo.exifDate,
            kCGImagePropertyTIFFSoftware: "StarSync Review Kit",
        ],
    ]
    CGImageDestinationAddImage(dest, ctx.makeImage()!, properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(demo.fileName)") }
}

// MARK: - MessagePack, only what these records need

indirect enum MP {
    case str(String), int(Int), map([(String, MP)])

    var bytes: [UInt8] {
        switch self {
        case .int(let v):
            precondition(v >= 0 && v <= 0xffff)
            if v <= 0x7f { return [UInt8(v)] }
            if v <= 0xff { return [0xcc, UInt8(v)] }
            return [0xcd, UInt8(v >> 8), UInt8(v & 0xff)]
        case .str(let s):
            let b = Array(s.utf8)
            if b.count <= 31 { return [0xa0 | UInt8(b.count)] + b }
            precondition(b.count <= 0xff)
            return [0xd9, UInt8(b.count)] + b
        case .map(let pairs):
            precondition(pairs.count <= 15)
            // An array of pairs rather than a dictionary, so the bytes come
            // out the same on every run.
            return [0x80 | UInt8(pairs.count)]
                + pairs.flatMap { MP.str($0.0).bytes + $0.1.bytes }
        }
    }
}

let user = "reviewkituser00000000000000000000"

var docs: [(id: String, type: String, subtype: String?, record: MP)] = []

for demo in demos {
    var record: [(String, MP)] = [
        ("type", .str("asset")),
        ("subtype", .str("image")),
        ("captureDate", .str(demo.capture)),
        ("importSource", .map([
            ("fileName", .str(demo.fileName)),
            ("originalWidth", .int(width)),
            ("originalHeight", .int(height)),
        ])),
        ("ratings", .map([(user, .map([("rating", .int(demo.rating))]))])),
    ]
    if let flag = demo.flag {
        record.append(("reviews", .map([(user, .map([("flag", .str(flag))]))])))
    }
    docs.append((demo.id, "asset", "image", .map(record)))
}

let albums: [(id: String, name: String, members: [Int])] = [
    ("album01", "StarSync Review", demos.map(\.number)),
    ("album02", "Five Stars", demos.filter { $0.rating == 5 }.map(\.number)),
]
for album in albums {
    docs.append((album.id, "album", "collection", .map([
        ("type", .str("album")), ("subtype", .str("collection")), ("name", .str(album.name)),
    ])))
    for n in album.members {
        let asset = String(format: "demo%04d", n)
        docs.append(("\(album.id)-\(asset)", "album_asset", nil, .map([
            ("type", .str("album_asset")),
            ("album", .map([("id", .str(album.id))])),
            ("asset", .map([("id", .str(asset))])),
        ])))
    }
}

// MARK: - The catalog

let catalogPath = library.appendingPathComponent("Managed Catalog.mcat").path
var db: OpaquePointer?
guard sqlite3_open(catalogPath, &db) == SQLITE_OK else { fatalError("cannot create catalog") }

func exec(_ sql: String) {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
        fatalError(String(cString: error!))
    }
}

// The same schema as the fixture, which is the subset of the real one the
// reader touches.
exec("""
CREATE TABLE docs(
    localDocId INTEGER PRIMARY KEY, fullDocId TEXT UNIQUE NOT NULL,
    winningRevSequence INTEGER, mostRecentRevSequence INTEGER,
    deleted BOOLEAN DEFAULT 0, hasConflicts BOOLEAN DEFAULT 0,
    annotation BLOB, spaceId TEXT, type TEXT, subtype TEXT);
CREATE TABLE revs(
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, localDocId INTEGER NOT NULL,
    revId TEXT NOT NULL, parentRevSequence INTEGER, current BOOLEAN,
    deleted BOOLEAN DEFAULT 0, content BLOB);
CREATE TABLE schemaVersion(version INTEGER);
INSERT INTO schemaVersion VALUES (9);
""")

let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
for (index, doc) in docs.enumerated() {
    let localID = index + 1
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, "INSERT INTO revs(localDocId, revId, current, content) VALUES (?,?,1,?)", -1, &stmt, nil)
    sqlite3_bind_int(stmt, 1, Int32(localID))
    sqlite3_bind_text(stmt, 2, "\(doc.id)-1", -1, transient)
    let blob = doc.record.bytes
    blob.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(blob.count), transient) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { fatalError("insert rev failed") }
    sqlite3_finalize(stmt)
    let rev = sqlite3_last_insert_rowid(db)

    sqlite3_prepare_v2(db, "INSERT INTO docs(localDocId, fullDocId, winningRevSequence, mostRecentRevSequence, type, subtype) VALUES (?,?,?,?,?,?)", -1, &stmt, nil)
    sqlite3_bind_int(stmt, 1, Int32(localID))
    sqlite3_bind_text(stmt, 2, doc.id, -1, transient)
    sqlite3_bind_int64(stmt, 3, rev)
    sqlite3_bind_int64(stmt, 4, rev)
    sqlite3_bind_text(stmt, 5, doc.type, -1, transient)
    if let subtype = doc.subtype { sqlite3_bind_text(stmt, 6, subtype, -1, transient) } else { sqlite3_bind_null(stmt, 6) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { fatalError("insert doc failed") }
    sqlite3_finalize(stmt)
}
exec("VACUUM")
sqlite3_close(db)

// MARK: - Instructions and the archive

let source = root.appendingPathComponent("docs/app-store/review-kit/Read Me.txt")
try fm.copyItem(at: source, to: kit.appendingPathComponent("Read Me.txt"))

let ditto = Process()
ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
// --norsrc and no --keepParent tricks: a plain zip that Archive Utility opens
// into one folder, named as it is here.
ditto.arguments = ["-c", "-k", "--norsrc", "--keepParent", kit.path, zip.path]
try ditto.run()
ditto.waitUntilExit()
guard ditto.terminationStatus == 0 else { fatalError("ditto failed") }

print("wrote \(docs.count) catalog records and \(demos.count) photos")
print("wrote \(zip.path)")
