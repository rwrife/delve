// swift-tools-version: 6.0
import PackageDescription

// DelveStore — persistence layer for Delve (GRDB/SQLite).
// Pure data package, Linux-testable by design. Zero-network by
// construction: GRDB/SQLite is a local storage engine only.
let package = Package(
    name: "DelveStore",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DelveStore", targets: ["DelveStore"]),
    ],
    dependencies: [
        .package(path: "../DelveKit"),
        // Pinned exact: the CI and native lanes must build the same GRDB
        // graph. GRDB vendors its own SQLite; it performs no networking.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "DelveStore",
            dependencies: [
                "DelveKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DelveStoreTests",
            dependencies: ["DelveStore", "DelveKit"],
            resources: [.copy("Fixtures/v1.sqlite")]
        ),
    ]
)
