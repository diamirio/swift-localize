// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-localize",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "swift-localize",
            targets: ["swift-localize"]
        ),
        .executable(
            name: "swift-localize-cli",
            targets: ["swift-localize-cli"]
        ),
    ],
    targets: [
        .target(
            name: "swift-localize"
        ),
        .executableTarget(
            name: "swift-localize-cli",
            dependencies: ["swift-localize"]
        ),
        .testTarget(
            name: "swift-localizeTests",
            dependencies: ["swift-localize"]
        ),
    ]
)
