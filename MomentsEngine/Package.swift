// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MomentsEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MomentsEngine",
            targets: ["MomentsEngine"]),
    ],
    targets: [
        .target(
            name: "MomentsEngine",
            dependencies: [],
            path: "Sources/MomentsEngine"
        ),
        .testTarget(
            name: "MomentsEngineTests",
            dependencies: ["MomentsEngine"],
            path: "Tests/MomentsEngineTests"
        ),
    ]
)
