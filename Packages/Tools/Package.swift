// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tools",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Tools", targets: ["Tools"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Tools", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "ToolsTests", dependencies: ["Tools", .product(name: "SonaryCore", package: "SonaryCore")]),
    ]
)
