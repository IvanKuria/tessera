// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KalshiKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "KalshiKit",
            targets: ["KalshiKit"]
        ),
        // A runnable validation/demo of the SDK. Useful where XCTest is
        // unavailable (e.g. a Command Line Tools-only machine without Xcode):
        // `swift run kalshi-smoke` exercises decoding + signing end-to-end.
        .executable(
            name: "kalshi-smoke",
            targets: ["kalshi-smoke"]
        ),
    ],
    targets: [
        .target(
            name: "KalshiKit"
        ),
        .executableTarget(
            name: "kalshi-smoke",
            dependencies: ["KalshiKit"]
        ),
        .testTarget(
            name: "KalshiKitTests",
            dependencies: ["KalshiKit"],
            resources: [.process("Fixtures")]
        ),
    ]
)
