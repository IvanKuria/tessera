// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArbEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArbEngine", targets: ["ArbEngine"]),
    ],
    dependencies: [
        .package(path: "../KalshiKit"),
        .package(path: "../PolymarketKit"),
    ],
    targets: [
        .target(
            name: "ArbEngine",
            dependencies: [
                .product(name: "KalshiKit", package: "KalshiKit"),
                .product(name: "PolymarketKit", package: "PolymarketKit"),
            ]
        ),
        .executableTarget(
            name: "arb-smoke",
            dependencies: [
                "ArbEngine",
                .product(name: "KalshiKit", package: "KalshiKit"),
                .product(name: "PolymarketKit", package: "PolymarketKit"),
            ]
        ),
        .testTarget(
            name: "ArbEngineTests",
            dependencies: ["ArbEngine"]
        ),
    ]
)
