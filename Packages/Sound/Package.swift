// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sound",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Sound", targets: ["Sound"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Sound", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "SoundTests", dependencies: ["Sound"]),
    ]
)
