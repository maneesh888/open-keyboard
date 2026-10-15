// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardLayout",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "KeyboardLayout", targets: ["KeyboardLayout"]),
        .executable(name: "NumberPadDemo", targets: ["NumberPadDemo"])
    ],
    targets: [
        .target(name: "KeyboardLayout"),
        .executableTarget(name: "NumberPadDemo", dependencies: ["KeyboardLayout"]),
        .testTarget(name: "KeyboardLayoutTests", dependencies: ["KeyboardLayout"])
    ]
)
