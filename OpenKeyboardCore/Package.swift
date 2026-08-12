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
    dependencies: [
        .package(path: "../Vendor/semantic-prompt-contract")
    ],
    targets: [
        .target(
            name: "OpenKeyboardCore",
            dependencies: [
                .product(name: "SemanticPromptContract", package: "semantic-prompt-contract")
            ]
        ),
        .testTarget(name: "OpenKeyboardCoreTests", dependencies: ["OpenKeyboardCore"])
    ]
)
