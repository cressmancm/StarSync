// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StarSyncCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StarSyncCore", targets: ["StarSyncCore"]),
        .executable(name: "starsync-catalog", targets: ["starsync-catalog"]),
    ],
    targets: [
        // A one-function C wrapper: sqlite3_db_config is variadic, which
        // Swift cannot call, and the catalog connection needs it.
        .target(name: "CSQLiteShim", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "StarSyncCore", dependencies: ["CSQLiteShim"]),
        .executableTarget(name: "starsync-catalog", dependencies: ["StarSyncCore"]),
        .testTarget(
            name: "StarSyncCoreTests",
            dependencies: ["StarSyncCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
