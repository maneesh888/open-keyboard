// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardLayout",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "KeyboardLayout", targets: ["KeyboardLayout"]),
               .library(name: "KeyboardEmoji", targets: ["KeyboardEmoji"]),
               .executable(name: "NumberPadDemo", targets: ["NumberPadDemo"])],
    targets: [
        .target(name: "KeyboardLayout"),
        .executableTarget(name: "NumberPadDemo", dependencies: ["KeyboardLayout"]),
        .target(name: "KeyboardEmoji", dependencies: ["KeyboardLayout"], exclude: ["CATALOGUE.md"], resources: [.process("Resources")]),
        .testTarget(name: "KeyboardEmojiTests", dependencies: ["KeyboardEmoji"]),
        .testTarget(name: "KeyboardLayoutTests", dependencies: ["KeyboardLayout"])
    ]
)
