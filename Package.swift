// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MZAppFoundation",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .visionOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "MZAppFoundation", targets: ["MZAppFoundationLocal"]),
        .library(name: "MZAppFoundationReporting", targets: ["MZAppFoundationReporting"]),
        .library(name: "MZAppFoundationLive", targets: ["MZAppFoundationLive"]),
        .library(name: "MZAppFoundationFirebase", targets: ["MZAppFoundationFirebase"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Pulse.git", exact: "5.2.1"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.27.0"),
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", exact: "5.88.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.19.2")
    ],
    targets: [
        .target(name: "MZAppFoundation", path: "Packages/Core/Sources/MZAppFoundation"),
        .target(name: "MZAppFoundationReporting", resources: [.process("Resources")]),
        .target(name: "MZAppFoundationLocal", dependencies: [
            .target(name: "MZAppFoundationReporting", condition: .when(platforms: [.iOS])),
            "MZAppFoundation",
            .product(name: "Pulse", package: "Pulse"),
            .product(name: "PulseUI", package: "Pulse")
        ]),
        .target(name: "MZAppFoundationLive", dependencies: [
            "MZAppFoundationLocal",
            "MZAppFoundation",
            .product(name: "RevenueCat", package: "purchases-ios"),
            .product(name: "Sentry", package: "sentry-cocoa")
        ]),
        .target(name: "MZAppFoundationFirebase", dependencies: [
            "MZAppFoundationLive",
            "MZAppFoundation",
            .product(name: "FirebaseCore", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS])),
            .product(name: "FirebaseAnalyticsCore", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS]))
        ])
    ],
    swiftLanguageModes: [.v6]
)
