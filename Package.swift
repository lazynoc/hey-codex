// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HeyCodex",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HeyCodex", targets: ["HeyCodex"]),
    ],
    targets: [
        .executableTarget(
            name: "HeyCodex",
            path: "Sources/HeyCodex"
        ),
        .testTarget(
            name: "HeyCodexTests",
            dependencies: ["HeyCodex"],
            path: "Tests/HeyCodexTests"
        ),
    ]
)
