// swift-tools-version: 6.2.1
import PackageDescription

let package = Package(
    name: "MZAppFoundation",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .visionOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "MZAppFoundation", targets: ["MZAppFoundationLocal"]),
        .library(name: "MZAppFoundationUI", targets: ["MZAppFoundationUI"]),
        .library(name: "MZAppFoundationReporting", targets: ["MZAppFoundationReporting"]),
        .library(name: "MZAppFoundationLive", targets: ["MZAppFoundationLive"]),
        .library(name: "MZAppFoundationRevenueCat", targets: ["MZAppFoundationRevenueCat"]),
        .library(name: "MZAppFoundationSentry", targets: ["MZAppFoundationSentry"]),
        .library(name: "MZAppFoundationFirebaseAnalytics", targets: ["MZAppFoundationFirebaseAnalytics"]),
        .library(name: "MZAppFoundationFirebase", targets: ["MZAppFoundationFirebase"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Pulse.git", exact: "5.2.1"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.30.2"),
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", exact: "5.94.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "13.0.1", traits: [])
    ],
    targets: [
        .target(name: "MZAppFoundation", path: "Packages/Core/Sources/MZAppFoundation"),
        .target(name: "MZAppFoundationUI", dependencies: ["MZAppFoundation"],
                path: "Packages/Core/Sources/MZAppFoundationUI"),
        .target(name: "MZAppFoundationReporting", resources: [.process("Resources")]),
        .target(name: "MZAppFoundationLocal", dependencies: [
            .target(name: "MZAppFoundationReporting", condition: .when(platforms: [.iOS])),
            "MZAppFoundation",
            "MZAppFoundationUI",
            .product(name: "Pulse", package: "Pulse"),
            .product(name: "PulseUI", package: "Pulse")
        ]),
        .target(name: "MZAppFoundationLive", dependencies: [
            "MZAppFoundationLocal",
            "MZAppFoundation",
            "MZAppFoundationRevenueCat",
            "MZAppFoundationSentry"
        ]),
        .target(name: "MZAppFoundationRevenueCat", dependencies: [
            "MZAppFoundation", .product(name: "RevenueCat", package: "purchases-ios")
        ]),
        .target(name: "MZAppFoundationSentry", dependencies: [
            "MZAppFoundation", .product(name: "Sentry", package: "sentry-cocoa")
        ]),
        .target(name: "MZAppFoundationFirebase", dependencies: [
            "MZAppFoundationLive",
            "MZAppFoundationLocal",
            "MZAppFoundationFirebaseAnalytics",
            "MZAppFoundation"
        ]),
        .target(name: "MZAppFoundationFirebaseAnalytics", dependencies: [
            "MZAppFoundation",
            .product(name: "FirebaseCore", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS])),
            .product(name: "FirebaseAnalyticsCore", package: "firebase-ios-sdk", condition: .when(platforms: [.iOS]))
        ])
    ],
    swiftLanguageModes: [.v6]
)
