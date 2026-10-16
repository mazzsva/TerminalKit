// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "TerminalKit",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .library(
            name: "TerminalKit",
            targets: ["TerminalKit"]
        ),
    ],
    targets: [
        .target(
            name: "TerminalCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "TerminalCoreTests",
            dependencies: ["TerminalCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "TerminalKit",
            dependencies: ["TerminalCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "TerminalKitTests",
            dependencies: ["TerminalKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
