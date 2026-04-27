// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BarKeeper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BarKeeper",
            path: "Sources",
            exclude: ["FoundryCheck"]
        ),
        .executableTarget(
            name: "FoundryCheck",
            path: "Sources/FoundryCheck"
        )
    ]
)
