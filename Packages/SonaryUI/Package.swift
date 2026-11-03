// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SonaryUI",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SonaryUI", targets: ["SonaryUI"])],
    
    targets: [
        .target(name: "SonaryUI"),
        .testTarget(name: "SonaryUITests", dependencies: ["SonaryUI"]),
    ]
)
