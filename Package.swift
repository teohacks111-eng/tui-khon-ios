// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TuiKhon",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        // xtool packages the single library product as the iOS application.
        .library(
            name: "TuiKhon",
            targets: ["TuiKhon"]
        ),
    ],
    targets: [
        .target(
            name: "TuiKhon"
        ),
        .testTarget(
            name: "TuiKhonTests",
            dependencies: ["TuiKhon"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
