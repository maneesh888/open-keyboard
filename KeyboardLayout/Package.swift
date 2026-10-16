// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardLayout",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "KeyboardLayout", targets: ["KeyboardLayout"]),
               .library(name: "OpenKeyboardEmoji", targets: ["OpenKeyboardEmoji"]),
               .executable(name: "NumberPadDemo", targets: ["NumberPadDemo"])],
    targets: [
        .target(name: "KeyboardLayout"),
        .executableTarget(name: "NumberPadDemo", dependencies: ["KeyboardLayout"]),
        .target(name: "OpenKeyboardEmoji", dependencies: ["KeyboardLayout"], exclude: ["CATALOGUE.md"], resources: [.process("Resources")]),
        .testTarget(name: "OpenKeyboardEmojiTests", dependencies: ["OpenKeyboardEmoji"]),
        .testTarget(name: "KeyboardLayoutTests", dependencies: ["KeyboardLayout"])
    ]
)
