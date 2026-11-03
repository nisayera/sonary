// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Display",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Display", targets: ["Display"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Display", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "DisplayTests", dependencies: ["Display"]),
    ]
)
