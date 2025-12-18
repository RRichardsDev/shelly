// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShellyPairingUI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShellyPairingUI",
            path: "Sources"
        )
    ]
)
