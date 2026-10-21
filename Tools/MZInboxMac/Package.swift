// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MZInboxMac",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "MZInbox", targets: ["MZInbox"])],
    targets: [
        .executableTarget(
            name: "MZInbox",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        )
    ],
    swiftLanguageModes: [.v6]
)
