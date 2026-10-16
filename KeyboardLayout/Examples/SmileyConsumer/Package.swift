// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmileyConsumer",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SmileyConsumer", targets: ["SmileyConsumer"])],
    dependencies: [.package(path: "../..")],
    targets: [.target(name: "SmileyConsumer", dependencies: [.product(name: "KeyboardLayout", package: "KeyboardLayout")])]
)
