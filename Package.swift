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
            dependencies: [.product(name: "MCP", package: "swift-sdk")],
            // An identity of its own (bundle id, version) inside the binary, so
            // macOS ties Accessibility and Screen Recording to backseat itself.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                           "-Xlinker", "scripts/release/Info.plist"])]
        ),
        // Small AppKit app the end-to-end tests drive in the background.
        .executableTarget(name: "BackseatFixture"),
    ],
    swiftLanguageModes: [.v5]
)
