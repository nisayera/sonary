// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Notch",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Notch", targets: ["Notch"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Notch", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "NotchTests", dependencies: ["Notch"]),
    ]
)
