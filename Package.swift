// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EverythingInOne",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EverythingInOne",
            path: "Sources/EverythingInOne"
        )
    ]
)
