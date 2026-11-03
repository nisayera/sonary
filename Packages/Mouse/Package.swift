// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mouse",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Mouse", targets: ["Mouse"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Mouse", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "MouseTests", dependencies: ["Mouse"]),
    ]
)
