// swift-tools-version:6.1
import PackageDescription

// The MCP server is a package of its own, so the root package and the app
// stay free of third-party code, also when they resolve (design 12.2).
let package = Package(
    name: "DesqueezeMCP",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "DesqueezeCore", path: ".."),
        // Not yet at 1.0: its API changes between minor versions.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.1")),
        // The library's own logging package, and at the library's own
        // requirement. Named here because the server uses its `Logger` type:
        // a transport must have one, and the server sends its log to
        // standard error. It adds no package to `Package.resolved`.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "desqueeze-mcp",
            dependencies: [
                .product(name: "DesqueezeCore", package: "DesqueezeCore"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        // The dependency on `desqueeze-mcp` builds the server before the
        // tests run. The tests start it as a child process.
        .testTarget(
            name: "DesqueezeMCPTests",
            dependencies: [
                "desqueeze-mcp",
                .product(name: "DesqueezeCore", package: "DesqueezeCore"),
                .product(name: "MCP", package: "swift-sdk"),
                // A test's stand-in for the library's transport has a `Logger`.
                .product(name: "Logging", package: "swift-log"),
            ]),
    ]
)
