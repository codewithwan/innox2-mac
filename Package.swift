// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InnoX2",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "InnoX2", path: "Sources/InnoX2", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
