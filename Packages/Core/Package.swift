// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MZAppFoundationCore",
    platforms: [.iOS(.v26), .visionOS(.v26), .macOS(.v15)],
    products: [.library(name: "MZAppFoundation", targets: ["MZAppFoundation"]),
               .library(name: "MZAppFoundationUI", targets: ["MZAppFoundationUI"])],
    targets: [
        .target(name: "MZAppFoundation"),
        .target(name: "MZAppFoundationUI", dependencies: ["MZAppFoundation"]),
        .testTarget(name: "MZAppFoundationTests", dependencies: ["MZAppFoundation"])
    ],
    swiftLanguageModes: [.v6]
)
