// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SonaryCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SonaryCore", targets: ["SonaryCore"])],
    
    targets: [
        .target(name: "SonaryCore"),
        .testTarget(name: "SonaryCoreTests", dependencies: ["SonaryCore"]),
    ]
)
