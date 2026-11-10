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
        .target(name: "StarSyncCore"),
        .executableTarget(name: "starsync-catalog", dependencies: ["StarSyncCore"]),
        .testTarget(
            name: "StarSyncCoreTests",
            dependencies: ["StarSyncCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
