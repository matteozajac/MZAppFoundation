# Integration

Requires Swift 6.2+, Xcode with iOS/visionOS 26 SDKs, and private GitHub access. Version 0.5.0 also supports macOS 15. Feature code uses the SDK-free `MZAppFoundation` core module; bootstrap and settings choose composition/UI products. Vendor SDK modules are never re-exported. SDK versions are pinned centrally.

The 0.5.0 products are `MZAppFoundation` (Pulse local composition), `MZAppFoundationUI` (core-only UI), and independent `MZAppFoundationRevenueCat`, `MZAppFoundationSentry`, and `MZAppFoundationFirebaseAnalytics` adapters. Existing `MZAppFoundationLive` (local + RevenueCat + Sentry) and `MZAppFoundationFirebase` (Live + iOS Firebase Analytics) remain compatibility umbrellas. These developer settings and independent adapters are first published in 0.5.0, which is the setup default.

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

Run setup against `.mzappfoundation/config.json` (copy `config.example.json` and replace identifiers). Bootstrap/entrypoint imports `MZAppFoundationLocal` and selected adapter modules. Feature files import just `MZAppFoundation`. Modern setup selects SDK products only for supplied provider configuration; older pinned integrations retain their compatible umbrella composition.

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
        #if os(visionOS) || os(macOS)
        DeveloperConsoleScene(options: services.developerOptions)
        FoundationSettingsScene(
            services: services,
            pages: FoundationDeveloperTools.pages(services: services)
        )
        #if os(macOS)
            .commands { FoundationSettingsCommands(services: services) }
        #endif
        #endif
    }
}
```

Use exactly one services composition per app process. Identical repeated live bootstrap returns the original object; change delivery through `services.telemetry.updatePreferences`, not by creating another composition. Persist delivery preferences in app-owned settings when needed and supply them at launch. Diagnostic revocation cancels the Sentry transport before closing the SDK, then removes its dedicated cache. Local logs remain available independently.

Register the developer tools modifier on the principal app scene. Multi-window apps should choose their active primary scene for presentation rather than sharing sheet state across all window roots. iOS uses a scoped responder for shake; apps with custom responders or text input should verify their responder-chain behavior. An explicit Settings button calls `requestConsole()` as a fallback. visionOS uses one console scene identifier and opens it on first launch when enabled; closing the console does not reopen it on ordinary scene updates.

Add `FoundationSettingsLink(services:pages:)` to the app's `List` or `Form`. Automatic presentation is an iOS sheet and a macOS/visionOS window with sidebar navigation; the latter requires `FoundationSettingsScene`. Pass the same app-owned pages to the link and scene. `presentation: .sheet` opts into sheet presentation without a settings scene. macOS `FoundationSettingsCommands` supplies Command–Option–D for settings and Command–Option–L for the console. The settings entry, content, and custom destinations are gated by developer access; disabling/expiry dismisses presented content. Read [developer settings](developer-settings.md) for the complete contract and examples.

## Independent adapter composition

`LocalServices.make` can retain Pulse while accepting `additionalAnalytics`, `additionalDiagnostics`, and an injected purchase provider. Its telemetry runtime/preference gates still apply to remote engines. Construct SDK adapters only in a permitted runtime, pass each owned adapter to its diagnostic builder, and keep one app-lifetime composition:

```swift
import MZAppFoundation
import MZAppFoundationLocal
import MZAppFoundationSentry

@MainActor func makeServices(configuration: AppConfiguration, schema: TelemetrySchema,
                            appSentryDSN: String) -> AppServices {
    let project = ProviderProjectIdentity(name: "My app", projectID: "1234")
    var inventory = SentryProvider.diagnostics(dsn: appSentryDSN, project: project)
    var remoteDiagnostics: [any DiagnosticsEngine] = []
    if RuntimeSafety.permitsRemote(environment: configuration.environment) {
        do {
            let engine = try SentryDiagnostics(dsn: appSentryDSN, configuration: configuration)
            remoteDiagnostics.append(engine)
            inventory = SentryProvider.diagnostics(dsn: appSentryDSN, project: project, engine: engine)
        } catch {
            inventory = SentryProvider.diagnostics(dsn: appSentryDSN, project: project,
                base: inventory, bootstrapFailure: true)
            inventory.bootstrapIssue = "Sentry could not start. Local diagnostics remain available."
            inventory = inventory.recordingStartup([
                .init(provider: .sentry, stage: .initialization, status: .failed,
                      code: "sentry.startup_failed", message: "The Sentry adapter could not be created.",
                      correction: "Check this app's DSN and remove competing SDK initialization.")
            ])
        }
    }
    return LocalServices.make(configuration: configuration, schema: schema,
        purchases: UnavailablePurchases(), foundationDiagnostics: inventory,
        additionalDiagnostics: remoteDiagnostics)
}
```

RevenueCat uses `RevenueCatPurchases(key:configuration:)` plus `RevenueCatProvider.diagnostics(publicKey:project:base:purchases:)`. iOS Firebase uses `FirebaseAnalyticsEngine(configuration:path:)` plus `FirebaseProvider.diagnostics(googleServiceInfoPath:projectName:engine:base:)`, injected through `additionalAnalytics`. Build inventory with the passive overload when no adapter can be constructed. `base:` preserves app expectations, build metadata, startup records, and custom inspections. Keep credentials in the app-owned bootstrap, never feature code or diagnostic snapshots.

`UnavailablePurchases` is the device fallback when purchases are not configured. `MockPurchases` and the separate local QA composition are explicit simulations; developer mode does not make mock entitlements production authorization. SDK-free `NoopAnalyticsEngine` and `NoopDiagnosticsEngine` are available alongside empty engine arrays.

## Build graph

| Target | SDK dependencies | Default behavior |
|---|---|---|
| Local simulator | Core, Pulse, PulseUI | Mock purchases, local telemetry, developer mode on |
| Device Debug | Selected configured SDK dependencies compiled | Runtime local services, developer mode on |
| Device Internal | Selected live adapters | Remote delivery follows app preferences, developer mode on |
| Device Release | Selected live adapters | Remote delivery follows app preferences, developer mode off |
| macOS local | Core, UI, Pulse | Native console/settings windows and local telemetry |
| Standalone core tests | Foundation/Observation only | Recording engines and mock purchases |

Explicit developer enable/disable preferences override defaults. `<scheme>://developer/enable` and `/disable` reject credentials, ports, queries, fragments and encoded alternate paths. Developer mode does not alter remote delivery or purchase access.

Version 0.5.0 standardizes `DeveloperOptions.preferenceKey` as `mzappfoundation.developer.enabled`, scoped to each supplied defaults store. It adds `mzappfoundation://<app-host>/developer/enable` and `/disable`; unique app-scheme aliases avoid ambiguous OS targeting when multiple apps register the shared scheme. Session/timed access stores false for the next launch, while saved choices persist. These choices never enable remote delivery or bypass purchase verification.

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

Provider fields: `revenuecat_public_key`, `sentry_dsn`, `google_service_info` (app-relative plist path), `sentry_org`, `sentry_project`. Modern integrations also accept `developer_link_host`, `revenuecat_project_name`, `revenuecat_project_id`, `revenuecat_app_id`, `firebase_project_name`, and `sentry_project_id`. Metadata alone does not cause SDK linkage or prove remote provisioning. Never store administrative tokens in this file. `products` contains only confirmed product definitions; provisioning is handled by the skill and records exact remote readbacks. No product catalog means no RevenueCat offering creation.

Setup defaults to `package_version: "0.5.0"`; use `package_path` when developing against a local checkout. An explicitly pinned 0.3.1 integration remains compatible and does not receive new settings/build APIs. Setup for 0.5.0+ supports iOS, visionOS, and macOS, generates independent provider composition, and copies the build metadata generator into the app. Review and validate the target app; setup does not publish a package, distribute the app, or migrate another repository.

## Build and diagnostics evidence

`VERSION` and library `Package.resolved` generate `FoundationVersion.swift`. The app build phase writes `MZFoundationBuildMetadata.plist` with optional app/foundation revisions, modified-tree flags, build channel/date, and app-resolved versions. Missing evidence stays unstamped; the library lock snapshot is explicitly labeled. Runtime SDK measurements are shown separately from generated package-version evidence.

`FoundationDiagnostics` accepts ordered environment/platform provider expectations, expected identities, startup records, typed app-owned inspections, and manual verification actions. The last matching expectation wins. Provider screens compare known expected/supplied/running identifiers and report unknown runtime identity without inventing a match. Firebase plist inspection remains available when its SDK is absent. The overview's issue filter selects warning/error findings.

Telemetry exposes payload-free counters and a bounded process-local timeline. Counts distinguish calls from per-adapter outcomes, so blocking reasons and multiple adapter results can overlap. Manual RevenueCat refresh preserves normal verification rules; tagged Firebase/Sentry events require current runtime/preferences and report submission with correlation references, requiring dashboard confirmation.

`services.diagnosticExport()` provides an immutable, versioned, redacted JSON/text snapshot. The developer UI can save/copy/share it. On iOS, opt into a report ZIP attachment with `DeveloperReporting(services: services)` or a diagnostics closure; the form then allows exclusion of the captured `diagnostics.json`. App-owned custom fields require explicit exportable IDs and safe technical values. Neither snapshots nor QA/report attachments are automatically uploaded through analytics/Sentry.

The local QA page creates isolated missing-configuration, offline, pending-purchase, and verification-failure mock services. It never replaces the host composition and requires a local debug/simulator/test/preview runtime. See [developer settings](developer-settings.md) for all screens, contracts, and [current validation evidence](developer-settings-validation.md).

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
