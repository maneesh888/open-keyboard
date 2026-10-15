// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardLayout",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "KeyboardLayout", targets: ["KeyboardLayout"]),
               .library(name: "OpenKeyboardEmoji", targets: ["OpenKeyboardEmoji"])],
    targets: [
        .target(name: "KeyboardLayout"),
        .target(name: "OpenKeyboardEmoji", dependencies: ["KeyboardLayout"], exclude: ["CATALOGUE.md"], resources: [.process("Resources")]),
        .testTarget(name: "OpenKeyboardEmojiTests", dependencies: ["OpenKeyboardEmoji"]),
        .testTarget(name: "KeyboardLayoutTests", dependencies: ["KeyboardLayout"])
    ]
)
