// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Diana", platforms: [.macOS(.v15)], products: [.executable(name: "Diana", targets: ["DianaApp"])],
    targets: [
        .target(name: "DianaCore"),
        .executableTarget(name: "DianaApp", dependencies: ["DianaCore"], resources: [.copy("Resources")]),
        .testTarget(name: "DianaCoreTests", dependencies: ["DianaCore"]),
    ])
