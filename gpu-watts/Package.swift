// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GPUWatts",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GPUWatts",
            path: "GPUWatts",
            exclude: ["Info.plist", "GPUWatts.entitlements"]
        )
    ]
)
