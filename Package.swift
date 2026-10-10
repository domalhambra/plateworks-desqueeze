// swift-tools-version:5.9
import PackageDescription

// No target here has a dependency outside this package. The MCP server links
// the MCP library, so it is a package of its own, in `MCPServer/`, and takes
// `DesqueezeCore` from this package by path (design, section 12.2).
let package = Package(
    name: "DesqueezeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesqueezeCore", targets: ["DesqueezeCore"]),
        .executable(name: "desqueeze", targets: ["desqueeze"]),
    ],
    targets: [
        .target(name: "DesqueezeCore"),
        // The command line tool as a library, so its tests can call it.
        .target(name: "DesqueezeCLI", dependencies: ["DesqueezeCore"]),
        .executableTarget(name: "desqueeze", dependencies: ["DesqueezeCLI"]),
        .testTarget(name: "DesqueezeCoreTests", dependencies: ["DesqueezeCore"]),
        // The dependency on `desqueeze` builds the tool before the tests
        // run. The end-to-end tests start it as a child process.
        .testTarget(name: "DesqueezeCLITests", dependencies: ["DesqueezeCLI", "DesqueezeCore", "desqueeze"]),
    ]
)
