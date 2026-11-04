// swift-tools-version:6.0
import PackageDescription

// RelayCore: protocol, SSH transport and model of the Relay gateway (see ~/relay/PROTOCOL.md).
// Platform-neutral so it builds and tests on Linux; the iOS app (App/, project.yml) links it.
let package = Package(
    name: "RelayCore",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "RelayCore", targets: ["RelayCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "RelayCore", dependencies: [.product(name: "Citadel", package: "Citadel")]),
        .executableTarget(name: "relay-smoke", dependencies: ["RelayCore"]),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
