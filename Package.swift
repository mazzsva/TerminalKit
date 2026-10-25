// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency")
]

let package = Package(
    name: "TerminalKit",
    platforms: [
        .macOS(.v27)
    ],
    products: [
        .library(
            name: "TerminalKit",
            targets: ["TerminalKit"]
        )
    ],
    targets: [
        .target(name: "CTerminalCore"),
        .target(
            name: "TerminalCore",
            dependencies: ["CTerminalCore"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "TerminalCoreTests",
            dependencies: ["TerminalCore"],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "TerminalKit",
            dependencies: ["TerminalCore"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "TerminalKitTests",
            dependencies: ["TerminalKit"],
            swiftSettings: swiftSettings,
        ),
    ]
)
