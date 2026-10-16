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
            name: "TerminalKit",
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
