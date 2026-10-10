# Integration

Requires Swift 6.2.3+, Xcode with iOS/visionOS 26 SDKs, and private GitHub access. Version 0.5.0 also supports macOS 15. Feature code uses the SDK-free `MZAppFoundation` core module; bootstrap and settings choose composition/UI products. Vendor SDK modules are never re-exported. SDK versions are pinned centrally.

The products are `MZAppFoundation` (Pulse local composition), `MZAppFoundationUI` (core-only UI), and independent `MZAppFoundationRevenueCat`, `MZAppFoundationSentry`, and `MZAppFoundationFirebaseAnalytics` adapters. Existing `MZAppFoundationLive` (local + RevenueCat + Sentry) and `MZAppFoundationFirebase` (Live + iOS Firebase Analytics) remain compatibility umbrellas. Developer settings and independent adapters were introduced in 0.5.0. Setup now defaults to 0.6.1. Modern integrations include keyboard help, Command–D console access, console presentation above existing iOS sheets/alerts, and short app-specific developer links.

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

For the iOS reporting path below, set `bug_reporting: true` in setup configuration. Setup generates one `MZBootstrap.reporting` instance and verifies the host's `NSMicrophoneUsageDescription`. Pass that instance to the modifier and reporting-aware settings pages to get the Ladybug action, recent screen activity and report ZIP. Without reporting configuration, keep `.appDeveloperTools(services.developerOptions)` and `FoundationDeveloperTools.pages(services:)` for the compatible console-only interface. Reporting capture is available on iOS only.

```swift
import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

@main struct MyApp: App {
    private let services = MZBootstrap.services
    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
                #if os(iOS)
                .appDeveloperTools(services.developerOptions, reporting: MZBootstrap.reporting)
                #else
                .appDeveloperTools(services.developerOptions)
                #endif
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

Register the developer tools modifier on the principal app scene. Multi-window apps should choose their active primary scene for presentation. On iOS, a scoped responder handles shake and Command–D, including while an app sheet is open. The console appears in a separate window in that scene; closing it restores the original window with its sheet or alert still presented. Apps with custom responders or text input should verify their responder-chain behavior. An explicit Settings button can call `requestConsole()`. visionOS uses one console scene identifier and opens it on first launch when enabled; closing the console does not reopen it on ordinary scene updates.

Add `FoundationSettingsLink(services:pages:)` to the app's `List` or `Form`. On iOS with reporting enabled, use `FoundationDeveloperTools.pages(services: services, reporting: MZBootstrap.reporting)` so the Pulse console entry opens the same reporter. Automatic presentation is an iOS sheet and a macOS/visionOS window with sidebar navigation; the latter requires `FoundationSettingsScene`. Pass the same app-owned pages to the link and scene. `presentation: .sheet` opts into sheet presentation without a settings scene. macOS `FoundationSettingsCommands` supplies Command–D for the console, Option–Command–L as an alias, and Control–Option–Command–D for settings. The settings entry, content, and custom destinations are gated by developer access; disabling/expiry dismisses presented content.

Add `FoundationKeyboardShortcutsLink(options: services.developerOptions, sections: appShortcuts)` to ordinary settings for help that remains readable with developer mode off. The package supplies its built-in developer shortcuts and the shared list UI; apps inject `FoundationKeyboardShortcutSection` values describing reader or other feature shortcuts. Bind feature actions with each `FoundationKeyboardShortcut.shortcut` so help and actions use the same definition. Help descriptions alone do not install those actions. Pass these sections through `keyboardShortcutSections:` to `FoundationSettingsLink`, `FoundationSettingsView`, and `FoundationSettingsScene`. The settings scene includes the help window on macOS/visionOS; `FoundationKeyboardShortcutsScene(options:sections:)` can also be registered independently, or the help link can use `presentation: .sheet`. Read [developer settings](developer-settings.md) for the full API and example.

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

### App-owned Firebase startup and Sentry privacy

Apps using Firebase App Check, Messaging or other backend services may initialize Firebase themselves, after installing their provider factories. Construct `FirebaseAnalyticsEngine(configuration: configuration, path: firebasePath, initialization: .reuseExistingDefaultApp)` only in a permitted runtime. This validates the already running default app against the supplied bundle/app/project identities and never initializes Firebase. Inject the engine through `LocalServices.make(additionalAnalytics:)`, and pass it to `FirebaseProvider.diagnostics(engine:)`. Analytics consent remains independent of backend startup. `managesAnalytics` indicates a valid Analytics binding; `ownsRunningSDK` remains false for reused apps. Replacement or identity changes block delivery and consent writes to the replacement. The default initialization mode still rejects an existing app.

For app-specific Sentry privacy, pass `eventFilter:` to `SentryDiagnostics`. Its `@Sendable (Event) -> Event?` callback runs synchronously on the delivery thread, after baseline PII removal; nil drops the event. The baseline user/request/extra removal runs again after the callback. Keep the filter stateless or thread-safe, never capture actor-isolated UI, and explicitly preserve any safe marker/correlation UUID needed for manual verification. Inject the engine through `additionalDiagnostics` and its passive provider builder. Do not initialize another Sentry SDK or replace telemetry preference gates.

Product event meaning, trigger points and domain-safe values belong to the app. Foundation validates the app-supplied schema and owns provider mapping, consent/runtime gates, counters and local sinks. Derive repeated allowlists from one app-owned definition. An adapter acceptance or submission is not backend ingestion.

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

Version 0.5.0 standardized `DeveloperOptions.preferenceKey` as `mzappfoundation.developer.enabled`, scoped to each supplied defaults store. Version 0.5.1 uses only `myapp://developer/enable` and `/disable`, where `myapp` is the app's registered unique URL scheme. Generate links with `DeveloperDeepLink.url(for:scheme:)`; no bundle identifier is included. The shared `mzappfoundation` scheme and old long app-host routes are rejected. Apple documents that the target app is undefined when multiple apps register one scheme, so current setup removes that shared registration. [Apple custom-scheme routing](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)

Session/timed access stores false for the next launch, while saved choices persist. These choices never enable remote delivery or bypass purchase verification. Command–D and shake open the console only while developer mode is enabled.

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

Provider fields: `revenuecat_public_key`, `sentry_dsn`, `google_service_info` (app-relative plist path), `sentry_org`, `sentry_project`. Modern integrations also accept `revenuecat_project_name`, `revenuecat_project_id`, `revenuecat_app_id`, `firebase_project_name`, and `sentry_project_id`. Metadata alone does not cause SDK linkage or prove remote provisioning. Never store administrative tokens in this file. `products` contains only confirmed product definitions; provisioning is handled by the skill and records exact remote readbacks. No product catalog means no RevenueCat offering creation.

Setup defaults to `package_version: "0.6.1"`; use `package_path` when developing against a local checkout. Explicitly pinned older integrations retain compatible generation and do not receive newer APIs until upgraded. Setup for 0.5.0+ supports iOS, visionOS, and macOS, generates independent provider composition, and copies the build metadata generator into the app. For 0.5.1+ or a current local checkout, it registers only the app's unique scheme and removes earlier shared-scheme entries while preserving unrelated URL types. Review and validate the target app; setup does not publish a package, distribute the app, or migrate another repository.

## Build and diagnostics evidence

`VERSION` and library `Package.resolved` generate `FoundationVersion.swift`. The app build phase writes `MZFoundationBuildMetadata.plist` with optional app/foundation revisions, modified-tree flags, build channel/date, and app-resolved versions. Missing evidence stays unstamped; the library lock snapshot is explicitly labeled. Runtime SDK measurements are shown separately from generated package-version evidence.

`FoundationDiagnostics` accepts ordered environment/platform provider expectations, expected identities, startup records, typed app-owned inspections, and manual verification actions. The last matching expectation wins. Provider screens compare known expected/supplied/running identifiers and report unknown runtime identity without inventing a match. Firebase plist inspection remains available when its SDK is absent. The overview's issue filter selects warning/error findings.

Telemetry exposes payload-free counters and a bounded process-local timeline. Counts distinguish calls from per-adapter outcomes, so blocking reasons and multiple adapter results can overlap. Manual RevenueCat refresh preserves normal verification rules; tagged Firebase/Sentry events require current runtime/preferences and report submission with correlation references, requiring dashboard confirmation.

`services.diagnosticExport()` provides an immutable, versioned, redacted JSON/text snapshot. The developer UI can save/copy/share it. On iOS, opt into a report ZIP attachment with `DeveloperReporting(services: services)` or a diagnostics closure; the form then allows exclusion of the captured `diagnostics.json`. App-owned custom fields require explicit exportable IDs and safe technical values. Neither snapshots nor QA/report attachments are automatically uploaded through analytics/Sentry.

The local QA page creates isolated missing-configuration, offline, pending-purchase, and verification-failure mock services. It never replaces the host composition and requires a local debug/simulator/test/preview runtime. See [developer settings](developer-settings.md) for all screens, contracts, and [current validation evidence](developer-settings-validation.md).

## Network diagnostics

Create `InstrumentedSession(options: services.developerOptions)` and use `data(for:)`. Capture follows the developer flag even for in-flight callbacks. It does not intercept vendor/background/custom sessions globally. Bodies, query values, credentials, raw error descriptions and metrics are omitted. Sensitive headers are filtered case-insensitively; extend `RedactionPolicy` for app-specific fields. URL paths must themselves be safe to record.

## SDK compatibility

Pulse is pinned to 5.2.1: 5.2.3 failed the visionOS sample build because `RichTextViewSearchToobar-ios.swift` calls `glassEffect`, which is unavailable on visionOS. Do not upgrade without both platform builds. RevenueCat 5.94.0, Sentry 9.30.1 and Firebase 13.0.0 are pinned. Firebase 13.0.0 is the canonical SwiftPM release; 13.0.1 has identical SwiftPM code. Unused Firestore package traits are disabled. Firebase's `FirebaseAnalyticsCore` package product exports the `FirebaseAnalytics` Swift module.

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
