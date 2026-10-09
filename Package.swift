// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesqueezeCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DesqueezeCore", targets: ["DesqueezeCore"])],
    targets: [
        .target(name: "DesqueezeCore"),
        .testTarget(name: "DesqueezeCoreTests", dependencies: ["DesqueezeCore"]),
    ]
)
