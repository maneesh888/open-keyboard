// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CompleteKeyboardConsumer",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.executable(name: "CompleteKeyboardConsumer", targets: ["CompleteKeyboardConsumer"])],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "CompleteKeyboardConsumer", dependencies: [
        .product(name: "KeyboardLayout", package: "KeyboardLayout"),
        .product(name: "KeyboardEmoji", package: "KeyboardLayout")
    ])]
)
