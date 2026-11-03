// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipboard",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Clipboard", targets: ["Clipboard"])],
    dependencies: [.package(path: "../SonaryCore"), .package(path: "../SonaryUI")],
    targets: [
        .target(name: "Clipboard", dependencies: [
            .product(name: "SonaryCore", package: "SonaryCore"),
            .product(name: "SonaryUI", package: "SonaryUI"),
        ],
        resources: [.process("Resources")]),
        .testTarget(name: "ClipboardTests", dependencies: ["Clipboard"]),
    ]
)
