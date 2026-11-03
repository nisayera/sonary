// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Keyboard",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Keyboard", targets: ["Keyboard"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Keyboard", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "KeyboardTests", dependencies: ["Keyboard"]),
    ]
)
