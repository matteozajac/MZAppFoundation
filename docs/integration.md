# Integration

Requires Swift 6.2+, Xcode with iOS/visionOS 26 SDKs, and private GitHub access. Root `Package.swift` exposes `MZAppFoundation` (Pulse local composition), `MZAppFoundationLive` (Pulse + RevenueCat + Sentry), and `MZAppFoundationFirebase` (live + iOS Firebase Analytics). All expose the same transitive `MZAppFoundation` core module. Vendor modules are never re-exported. SDK versions are pinned centrally.

## Feature code

```swift
import MZAppFoundation

@MainActor final class CheckoutModel {
    private let purchases: any PurchaseProviding
    private let analytics: any AnalyticsTracking
    init(purchases: any PurchaseProviding, analytics: any AnalyticsTracking) {
        self.purchases = purchases
        self.analytics = analytics
    }
}
```

App events conform to `AnalyticsEvent` and are registered in `TelemetrySchema`. Properties are typed values; undeclared events/properties are dropped. Do not include private data in declared strings, diagnostic codes, or log messages: key filtering is not semantic content classification. Purchase errors use `PurchaseFailure`; ownership uses `EntitlementState`. Apps own paywall UI and map entitlements into their own business rules.

## Bootstrap and scenes

Run setup against `.mzappfoundation/config.json` (copy `config.example.json` and replace identifiers). Only bootstrap/entrypoint imports `MZAppFoundationLocal` and applicable live composition modules. Feature files import just `MZAppFoundation`.

```swift
import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

@main struct MyApp: App {
    private let services = MZBootstrap.services
    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
                .appDeveloperTools(services.developerOptions)
        }
        #if os(visionOS)
        DeveloperConsoleScene(options: services.developerOptions)
        #endif
    }
}
```

Use exactly one services composition per app process. Identical repeated live bootstrap returns the original object; change delivery through `services.telemetry.updatePreferences`, not by creating another composition. Persist delivery preferences in app-owned settings when needed and supply them at launch. Diagnostic revocation cancels the Sentry transport before closing the SDK, then removes its dedicated cache. Local logs remain available independently.

Register the developer tools modifier on the principal app scene. Multi-window apps should choose their active primary scene for presentation rather than sharing sheet state across all window roots. iOS uses a scoped responder for shake; apps with custom responders or text input should verify their responder-chain behavior. An explicit Settings button calls `requestConsole()` as a fallback. visionOS uses one console scene identifier and opens it on first launch when enabled; closing the console does not reopen it on ordinary scene updates.

## Build graph

| Target | SDK dependencies | Default behavior |
|---|---|---|
| Local simulator | Core, Pulse, PulseUI | Mock purchases, local telemetry, developer mode on |
| Device Debug | Live dependencies compiled | Runtime local services, developer mode on |
| Device Internal | Live adapters | Remote delivery on, developer mode on |
| Device Release | Live adapters | Remote delivery on, developer mode off |
| Standalone core tests | Foundation/Observation only | Recording engines and mock purchases |

Explicit developer enable/disable preferences override defaults. `<scheme>://developer/enable` and `/disable` reject credentials, ports, queries, fragments and encoded alternate paths. Developer mode does not alter remote delivery or purchase access.

Heavy SDKs may be resolved/downloaded by Xcode because they exist in the package manifest. Local targets must not compile/link them. Test domain modules against the standalone `Packages/Core` package from a pinned checkout to avoid even dependency resolution. Do not use app-hosted unit tests when claiming an SDK-free test process.

## Setup commands

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements.txt
.venv/bin/python scripts/setup.py inspect --app-root /path/to/app
.venv/bin/python scripts/setup.py apply --app-root /path/to/app
.venv/bin/python scripts/setup.py verify --app-root /path/to/app
```

XcodeGen projects require `xcodegen`. Native Xcode projects require Ruby and `bundle install --gemfile scripts/Gemfile`; set `RUBY` when system Ruby differs. Native setup preserves source/resource/framework references and adds a local target. Review custom target dependencies, inherited xcconfigs, script phases, extensions and vendor calls: verification intentionally rejects unresolved direct SDK imports. Run setup from the project root; nested project specs should use project-root-relative paths.

Provider fields: `revenuecat_public_key`, `sentry_dsn`, `google_service_info` (app-relative plist path), `sentry_org`, `sentry_project`. Never store administrative tokens in this file. `products` contains only confirmed product definitions; provisioning is handled by the global skill and records exact remote readbacks. No product catalog means no RevenueCat offering creation.

## Network diagnostics

Create `InstrumentedSession(options: services.developerOptions)` and use `data(for:)`. Capture follows the developer flag even for in-flight callbacks. It does not intercept vendor/background/custom sessions globally. Bodies, query values, credentials, raw error descriptions and metrics are omitted. Sensitive headers are filtered case-insensitively; extend `RedactionPolicy` for app-specific fields. URL paths must themselves be safe to record.

## SDK compatibility

Pulse is pinned to 5.2.1: 5.2.3 failed the visionOS sample build because `RichTextViewSearchToobar-ios.swift` calls `glassEffect`, which is unavailable on visionOS. Do not upgrade without both platform builds. RevenueCat 5.88.0, Sentry 9.27.0 and Firebase 12.19.2 are pinned. Firebase's `FirebaseAnalyticsCore` package product exports the `FirebaseAnalytics` Swift module.

## Structured diagnostic logging (0.2.0)

Use the injected `services.logger` for technical logging:

```swift
logger.error("Model loading failed", error: error, category: "model",
             metadata: ["model_id": .string(modelID)])
```

`LogEntry` and `DiagnosticIssue` retain optional `ErrorSnapshot` and `LogSource` values.
Wrappers forward caller file/function/line. Error snapshots are synchronous, immutable,
and SDK-independent: type, domain, signed code, at most eight underlying causes,
and up to 64 stack frames. Supplied `ErrorStackProviding` stacks retain their provenance;
otherwise frames are explicitly labeled as reporting-time evidence. Arbitrary
localized descriptions and userInfo are excluded; app-owned `LoggableError` messages
must be audited, technical text. Never interpolate user-authored text into these messages.

AppServices routes error logs once through diagnostics; the raw local sink handles
Pulse persistence. Warnings remain local. Pulse shows error evidence in metadata and
caller location in its native source fields; Sentry receives exception and diagnostic
context fields only when remote diagnostics are enabled. App/build context stays in
metadata/session information, and analytics names are never rewritten for display.

Pulse 5.2.1 strips whitespace from metadata passed to `storeMessage`. The adapter
uses normal store insertion, then corrects the identified row on Pulse's public
Core Data write context, before returning. Frames use separate fields because
Pulse's metadata format is newline-delimited. This compatibility workaround stays
inside the Pulse adapter and is covered by a persistence test. Error/warning logs
with whitespace incur an immediate local save; ordinary token/numeric metadata
continues through Pulse's normal batching. The console defaults to Logs.

## Local bug reporting (0.3.0)

The optional iOS `MZAppFoundationReporting` module supplies rolling silent screen capture, screenshots, title-or-voice reports and ZIP sharing. `MZAppFoundationLocal` adapts the existing Pulse store and owns console integration. Add `bug_reporting: true` to setup configuration and follow [bug reporting integration](bug-reporting.md). The previous console-only interface remains source-compatible. No reporting types or third-party SDKs enter the standalone core package.
