// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Floatlate",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Floatlate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
