// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileConverter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FileConverter", path: "Sources/FileConverter")
    ]
)
