// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Monitor",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Monitor", targets: ["Monitor"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Monitor", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ]),
        .testTarget(name: "MonitorTests", dependencies: ["Monitor"]),
    ]
)
