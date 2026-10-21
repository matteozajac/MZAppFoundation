# MZAppFoundation

Shared infrastructure for Swift apps on iOS, visionOS, and macOS: typed telemetry, injectable purchases, structured error logging, and developer tools. Use the dependency-free core on its own, add Pulse for local diagnostics, or compose optional RevenueCat, Sentry, and Firebase Analytics adapters.

Feature code depends on package-owned protocols and values. Vendor SDK types stay inside adapter modules. Apps retain ownership of their event schema, delivery preferences, paywall, purchase access rules, and backend services.

## Requirements

- Swift 6.2.3 or later; Swift 6 language mode.
- iOS 26+, visionOS 26+, or macOS 15+; Xcode with the SDK for the platform you build.
- Optional tooling: XcodeGen 2.44+ for the samples, Python 3.11+ for repository scripts, and Ruby/Bundler for native Xcode project setup.

This checkout reports **0.6.2** in `VERSION`; installation examples pin that version. Pin a reviewed tag or revision for your app. APIs may change before 1.0.

Version 0.6.2 requires explicit opt-in to screen video recording in Developer Settings. Developer access alone does not enable recording. App-owned Firebase reuse and Sentry event filters are available through the adapter APIs.

## Install with Swift Package Manager

In Xcode, add `https://github.com/matteozajac/MZAppFoundation.git` as a package dependency and select only the products you need. For a Swift package using the local diagnostics composition:

```swift
dependencies: [
    .package(url: "https://github.com/matteozajac/MZAppFoundation.git", exact: "0.6.2")
],
targets: [
    .target(name: "MyFeature", dependencies: [
        .product(name: "MZAppFoundation", package: "MZAppFoundation")
    ])
]
```

This root product links Pulse. Import `MZAppFoundation` for core interfaces and `MZAppFoundationLocal` for `LocalServices` and the Pulse developer tools. Although unselected adapters need not be linked, SwiftPM can still resolve and download dependencies declared by the root manifest.

### Dependency-free core example

To avoid vendor SDK resolution entirely, clone a reviewed checkout and use its nested `Packages/Core` package as a **local path dependency**. SwiftPM cannot select a repository subdirectory in a remote package URL. The nested package shares its core/UI sources with the root package; choose one manifest per target graph.

With `FoundationDemo` beside the `MZAppFoundation` checkout, create this `FoundationDemo/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FoundationDemo",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../MZAppFoundation/Packages/Core")],
    targets: [
        .executableTarget(name: "FoundationDemo", dependencies: [
            .product(name: "MZAppFoundation", package: "Core")
        ])
    ]
)
```

Create `FoundationDemo/Sources/FoundationDemo/main.swift`:

```swift
import MZAppFoundation

@main
struct FoundationDemo {
    @MainActor
    static func main() {
        let configuration = AppConfiguration(
            bundleIdentifier: "com.example.demo",
            urlScheme: "foundationdemo",
            environment: .local,
            preferences: .init(analytics: false, diagnostics: false)
        )
        let telemetry = Telemetry(
            configuration: configuration,
            schema: TelemetrySchema(events: ["app_opened": []])
        )
        telemetry.track(TelemetryEvent("app_opened"))
        print("Tracked calls: \(telemetry.counters.analytics.attempts)")
    }
}
```

Run `swift run --package-path FoundationDemo` from their parent directory. It prints `Tracked calls: 1`. No delivery engines are configured: the example exercises schema validation and counters without sending telemetry or initializing a provider.

## Products and platforms

The platform columns describe the APIs in this checkout, not device or provider runtime certification.

| Manifest / product | Purpose and dependencies | Platform APIs |
|---|---|---|
| `Packages/Core`: `MZAppFoundation` | Protocols, telemetry routing, diagnostics, mocks; no third-party dependencies | iOS, visionOS, macOS |
| `Packages/Core`: `MZAppFoundationUI` | SwiftUI settings, provider diagnostics, keyboard help; core only | iOS, visionOS, macOS |
| Root: `MZAppFoundation` | Core, UI, Pulse/PulseUI local composition; includes reporting on iOS | iOS, visionOS, macOS |
| Root: `MZAppFoundationUI` | Core-only SwiftUI UI; root dependency resolution still applies | iOS, visionOS, macOS |
| Root: `MZAppFoundationReporting` | Screenshots, optional voice notes and recent silent screen history, report ZIP sharing; Apple frameworks | iOS only |
| Root: `MZAppFoundationRevenueCat` | Purchase adapter; RevenueCat | iOS, visionOS, macOS |
| Root: `MZAppFoundationSentry` | Diagnostic adapter; Sentry | iOS, visionOS, macOS |
| Root: `MZAppFoundationFirebaseAnalytics` | Analytics adapter; Firebase Core/AnalyticsCore | iOS; unavailable adapter on other platforms |
| Root: `MZAppFoundationLive` | Compatibility composition: local + RevenueCat + Sentry | iOS, visionOS, macOS |
| Root: `MZAppFoundationFirebase` | Compatibility composition: Live + Firebase Analytics | Analytics on iOS; Live composition elsewhere |

The root manifest pins Pulse 5.2.1, RevenueCat 5.94.0, Sentry 9.30.1, and Firebase 13.0.0. Consult the manifest and resolved files for the checkout you actually use.

Developer mode controls access to local tools. It does not grant purchase access or change remote delivery preferences. Event/property allowlists and key redaction reduce accidental exposure; apps must still keep private content out of messages, values, and URL paths.

## Samples and validation

From the repository root:

```sh
swift test --package-path Packages/Core
cd Samples
xcodegen generate
```

Open `Samples/MZFoundationSamples.xcodeproj` from the repository root. `FoundationLocal` and `FoundationVisionLocal` target simulators; `FoundationMacLocal` runs on macOS. Sample purchases are simulated, and the samples contain no provider credentials or real purchase catalog. The device schemes compile compatibility adapters without provisioning remote resources.

See [verification](docs/verification.md) for supported checks and their limits, [integration](docs/integration.md) for manual composition and setup tooling, and [migration](docs/migration.md) for adapting an existing app.

## Optional tools

The bundled [setup skill](skills/mz-app-foundation-setup/SKILL.md), [logging skill](skills/app-logging/SKILL.md), and [bug-report inspection skill](skills/app-bug-report/SKILL.md) can assist an agent working in an app repository. Install the repo-backed skills with `python3 scripts/install_skill.py`; this creates symlinks in the configured Codex skills directory. Review the workflow before applying it to an existing project.

**MZ Inbox is unreleased companion tooling.** Its [Mac menu bar receiver](Tools/MZInboxMac/README.md) watches a shared folder for report ZIPs, keeps a private local queue, and can dispatch Codex investigations or prepare changes in a separate worktree. The optional phone shortcut uses iCloud Drive for delivery. It is separate from the Swift package, requires its own setup, and does not establish physical-device transfer or provider runtime validation. Read the [report inbox guide](docs/report-inbox.md) before enabling automated processing.

## Project information

See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), [Changelog](CHANGELOG.md), [License](LICENSE), and [third-party notices](THIRD_PARTY_NOTICES.md). The [publication audit](docs/open-source-audit.md) records the review scope, source provenance, and validation results.
