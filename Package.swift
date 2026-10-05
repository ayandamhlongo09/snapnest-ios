// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapNest",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CaptureCore", targets: ["CaptureCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CaptureCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "QueueProbe", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"])
    ]
)
