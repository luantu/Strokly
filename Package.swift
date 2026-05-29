// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Strokly",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Strokly", targets: ["Strokly"]),
        .executable(name: "StroklyCoreChecks", targets: ["StroklyCoreChecks"]),
        .library(name: "StroklyCore", targets: ["StroklyCore"])
    ],
    targets: [
        .target(
            name: "StroklyCore",
            path: "Sources/StroklyCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Strokly",
            dependencies: ["StroklyCore"],
            path: "Sources/StroklyApp"
        ),
        .executableTarget(
            name: "StroklyCoreChecks",
            dependencies: ["StroklyCore"],
            path: "Tests/StroklyCoreChecks"
        )
    ]
)
