// swift-tools-version: 6.0
import PackageDescription

// DelveKit — pure-domain core for Delve (fixed-dungeon puzzle crawler).
// Pure Swift 6, no UIKit/SpriteKit/GRDB/Network: deterministic world rules
// must stay Linux-testable in CI.
let package = Package(
    name: "DelveKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DelveKit", targets: ["DelveKit"]),
    ],
    targets: [
        .target(
            name: "DelveKit",
            resources: [
                .copy("Resources/content-v1.json"),
            ]
        ),
        .testTarget(name: "DelveKitTests", dependencies: ["DelveKit"]),
    ]
)
