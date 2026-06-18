// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PolymarketKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PolymarketKit",
            targets: ["PolymarketKit"]
        ),
        // A runnable validation/demo of the SDK. Useful where XCTest is
        // unavailable (e.g. a Command Line Tools-only machine without Xcode):
        // `swift run pm-smoke` exercises decoding end-to-end, and
        // `swift run pm-smoke --live` fetches live Gamma + CLOB data.
        .executable(
            name: "pm-smoke",
            targets: ["pm-smoke"]
        ),
    ],
    targets: [
        .target(
            name: "PolymarketKit"
        ),
        .executableTarget(
            name: "pm-smoke",
            dependencies: ["PolymarketKit"]
        ),
        .testTarget(
            name: "PolymarketKitTests",
            dependencies: ["PolymarketKit"],
            resources: [.process("Fixtures")]
        ),
    ]
)
