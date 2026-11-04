// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Windows",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Windows", targets: ["Windows"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Windows", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "WindowsTests", dependencies: [
            "Windows", .product(name: "SonaryCore", package: "SonaryCore"),
        ]),
    ]
)
