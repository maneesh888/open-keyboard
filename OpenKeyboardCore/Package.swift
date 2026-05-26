// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenKeyboardCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "OpenKeyboardCore", targets: ["OpenKeyboardCore"])
    ],
    targets: [
        .target(name: "OpenKeyboardCore"),
        .testTarget(name: "OpenKeyboardCoreTests", dependencies: ["OpenKeyboardCore"])
    ]
)
