// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Apps",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Apps", targets: ["Apps"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Apps", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "AppsTests", dependencies: ["Apps"]),
    ]
)
