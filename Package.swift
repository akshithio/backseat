// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "backseat",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "backseat",
            dependencies: [.product(name: "MCP", package: "swift-sdk")]
        ),
        // Small AppKit app the end-to-end tests drive in the background.
        .executableTarget(name: "BackseatFixture"),
    ],
    swiftLanguageModes: [.v5]
)
