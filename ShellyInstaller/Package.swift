// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShellyInstaller",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShellyInstaller",
            path: "Sources"
        )
    ]
)
