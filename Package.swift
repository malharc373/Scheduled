// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Scheduled",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Scheduled",
            path: "Sources/Scheduled",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
