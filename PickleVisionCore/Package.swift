// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PickleVisionCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "PickleVisionCore", targets: ["PickleVisionCore"]),
    ],
    targets: [
        .target(name: "PickleVisionCore"),
        .testTarget(name: "PickleVisionCoreTests", dependencies: ["PickleVisionCore"]),
    ]
)
