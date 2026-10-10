# MZAppFoundation 0.6.0

Apps can retain their Firebase backend bootstrap while injecting the Foundation Analytics adapter, and apply their own Sentry privacy policy without copying the library.

## Host integrations

- `FirebaseAnalyticsEngine(configuration:path:initialization:)` defaults to `.initializeDefaultApp`, preserving existing calls. `.reuseExistingDefaultApp` requires an already initialized default app with matching bundle, Google app and project identities. It never initializes Firebase. Consent/delivery control belongs to the adapter; Firebase startup ownership remains external. Object replacement blocks delivery and consent writes to the replacement.
- `SentryDiagnostics(dsn:configuration:eventFilter:)` accepts an optional `@Sendable (Event) -> Event?`. The filter runs on the SDK delivery thread after baseline user/request/extra removal; those fields are removed again afterwards. Return nil to drop an event. Filters must be synchronous, thread-safe and privacy-safe. Runtime and transport revocation still apply.
- Binary inspection uses actual module/class/resource evidence and checks embedded extensions, avoiding false positives from app-owned type names.
- Pulse metadata repair stays on its background queue without blocking the main actor or console save observers. `PulseLogger.flush()` provides an asynchronous barrier for tests and exports.

## SDK policy

Exact pins: Pulse 5.2.1, Sentry 9.30.1, RevenueCat 5.94.0, Firebase 13.0.0. Firebase requires Swift 6.2.3/Xcode 26.2 or later. Firestore traits are disabled because the Foundation Analytics adapter does not use Firestore. Existing consuming apps may enable that trait when needed.

Use the latest stable SDKs on each release, then lock and test the graph. Run `python3 scripts/check_dependency_versions.py --check` before publication. Pulse 5.2.1 is an explicit temporary exception: 5.2.3's PulseUI search toolbar calls an API unavailable on visionOS. Firebase 13.0.1 is a Zip/Carthage release with identical SwiftPM code to the canonical 13.0.0 release. Newer releases are not silently covered by these exceptions.

The setup default, VERSION, generated metadata and samples use 0.6.0. XcodeGen and native projects both select the exact configured Foundation release. Existing explicit older pins remain supported. CI runs the adapter, reporting and developer-access contract suites. No other app migration, provider provisioning or physical-device acceptance is implied by this release.

## Release validation (2026-10-10)

- SDK-free core: 52 tests passed.
- iOS adapter contracts: 16 passed, including explicit Firebase reuse, identity/ownership conflicts, consent revocation, Sentry filtering and synchronous/asynchronous Pulse persistence.
- iOS reporting: 34 passed. Developer presentation/access host suite: 4 passed.
- Python setup, metadata, binary-audit and dependency-policy tooling: 64 passed.
- iOS local/device, visionOS local/device and native macOS local builds succeeded.
- iOS, visionOS and macOS local binaries contained Pulse and no RevenueCat, Sentry or Firebase Analytics/GoogleAppMeasurement SDK evidence.
- Live release check accepted the four exact SDK pins and only the documented Pulse/Firebase exceptions.

These checks do not establish physical-device provider ingestion, crash symbolication, store purchases or report/media delivery.
