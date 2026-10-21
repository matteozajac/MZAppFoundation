# Integration

This checkout requires Swift 6.2.3 in Swift 6 language mode and targets iOS 26+, visionOS 26+, and macOS 15+. Its `VERSION` and setup default are `0.6.2`. Use the manifests and source at your app's pinned revision when integrating another release.

See the [README](../README.md) for SwiftPM installation, the full product/platform matrix, and a compiling dependency-free example. The root `MZAppFoundation` **product** includes the Pulse local composition; the `MZAppFoundation` **module** contains SDK-independent interfaces. `Packages/Core` is a separate, local-path package with no third-party dependencies. Do not add both manifests to one target graph.

## Feature code

Inject protocols into app features instead of importing vendor SDKs:

```swift
import MZAppFoundation

@MainActor
final class CheckoutModel {
    private let purchases: any PurchaseProviding
    private let analytics: any AnalyticsTracking

    init(purchases: any PurchaseProviding, analytics: any AnalyticsTracking) {
        self.purchases = purchases
        self.analytics = analytics
    }
}
```

Events conform to `AnalyticsEvent` or use `TelemetryEvent`. Register their names and allowed property keys in `TelemetrySchema`; unknown events are rejected and undeclared properties are dropped. Properties use `TelemetryValue`. Key filtering does not inspect the meaning of a value: never put private content in allowed strings, diagnostic codes, log messages, or URL paths.

Apps own paywalls, product definitions, and the mapping from `EntitlementState` to feature access. `UnavailablePurchases` expresses an absent purchase provider. `MockPurchases` is an explicit simulation for local development or tests, not production purchase authorization.

## Manual local composition

Link the root `MZAppFoundation` product, then construct one services object for the app process:

```swift
import MZAppFoundation
import MZAppFoundationLocal

@MainActor
func makeLocalServices() -> AppServices {
    LocalServices.make(
        configuration: AppConfiguration(
            bundleIdentifier: "com.example.myapp",
            urlScheme: "myapp",
            environment: .local,
            preferences: .init(analytics: false, diagnostics: false)
        ),
        schema: TelemetrySchema(events: ["app_opened": []]),
        purchases: UnavailablePurchases()
    )
}
```

`LocalServices.make` retains Pulse logging and local telemetry. Remote delivery preferences do not disable local logging. Supply an app-owned `UserDefaults` store or `RedactionPolicy` when needed. Keep feature code on `services.analytics`, `services.diagnostics`, `services.logger`, and `services.purchases`.

## Developer tools and scenes

Apply `.appDeveloperTools(services.developerOptions)` to the primary SwiftUI view. Add `FoundationSettingsLink(services:pages:)` to an app `List` or `Form`, using `FoundationDeveloperTools.pages(services:)` for built-in pages.

On macOS and visionOS, register `DeveloperConsoleScene(options:)` and `FoundationSettingsScene(services:pages:)` in the `App` scene body for window presentation. Pass the same page definitions to the settings link and scene. The link's `presentation: .sheet` can instead use sheet presentation. On macOS, `.commands { FoundationSettingsCommands(services: services) }` adds console and settings commands to the settings scene. See [developer settings](developer-settings.md) for complete scene, keyboard-help, and custom-page examples.

The scoped iOS modifier handles shake and Command–D console requests. Check responder behavior in apps with custom text input, multiple windows, sheets, or alerts. Register the modifier on the scene that should own presentation. An explicit button can call `services.developerOptions.requestConsole()`.

Developer access defaults to enabled outside production unless a saved choice overrides it. `DeveloperOptions.preferenceKey` is `mzappfoundation.developer.enabled`, scoped to the supplied defaults store. Session and timed access do not persist an enabled state into the next launch. Developer access does not alter telemetry permissions or purchase verification.

Register an app-specific URL scheme. `DeveloperDeepLink.url(for:scheme:)` creates `myapp://developer/enable` or `myapp://developer/disable`; the shared `mzappfoundation` scheme and legacy long routes are rejected by the current API. The handler rejects extra credentials, ports, queries, fragments, and alternate paths. Preserve unrelated app deep links when adding this handler.

### iOS report sharing

The optional iOS reporting APIs provide screenshots, recent silent screen activity, optional voice notes, Pulse attachments, and report ZIP sharing. They do not automatically upload reports. Keep one `DeveloperReporting` instance beside the services composition:

```swift
#if os(iOS)
import MZAppFoundation
import MZAppFoundationLocal

@MainActor
func makeReporting(services: AppServices) -> DeveloperReporting {
    DeveloperReporting(services: services, archivePrefix: "myapp")
}
#endif
```

Screen video recording defaults off in 0.6.2. The user enables **Record screen video** explicitly in Developer Settings; developer access and local/internal builds do not opt the user in. Screenshots, logs, and manual voice notes remain available with video disabled.

Pass that same instance to `.appDeveloperTools(services.developerOptions, reporting: reporting)` and `FoundationDeveloperTools.pages(services: services, reporting: reporting)`. The host must supply an accurate `NSMicrophoneUsageDescription` before enabling voice notes. Capture behavior and microphone permission need physical-device checks; a build is not that evidence. Follow [bug reporting](bug-reporting.md) for recording limits, archive contents, and lifecycle details.

## Optional provider adapters

Link each configured adapter product explicitly. Construct remote adapters only when `RuntimeSafety.permitsRemote(environment:)` allows it. The runtime gate blocks simulator, local, preview, and recognized test processes; current delivery preferences additionally gate remote engine delivery. Persist those preferences in app-owned settings and update `services.telemetry.updatePreferences(...)` instead of recreating the composition.

`LocalServices.make` accepts an injected purchase provider, `additionalAnalytics`, `additionalDiagnostics`, and `foundationDiagnostics`. For example, the Sentry product can supply a remote diagnostics engine while retaining local Pulse logs:

```swift
import MZAppFoundation
import MZAppFoundationLocal
import MZAppFoundationSentry

@MainActor
func makeServices(configuration: AppConfiguration, schema: TelemetrySchema,
                  appSentryDSN: String) -> AppServices {
    var inventory = SentryProvider.diagnostics(dsn: appSentryDSN)
    var engines: [any DiagnosticsEngine] = []
    if RuntimeSafety.permitsRemote(environment: configuration.environment) {
        do {
            let engine = try SentryDiagnostics(dsn: appSentryDSN, configuration: configuration)
            engines.append(engine)
            inventory = SentryProvider.diagnostics(dsn: appSentryDSN, engine: engine)
        } catch {
            inventory = SentryProvider.diagnostics(
                dsn: appSentryDSN, base: inventory, bootstrapFailure: true
            )
            inventory.bootstrapIssue = "Sentry could not start. Local diagnostics remain available."
        }
    }
    return LocalServices.make(
        configuration: configuration, schema: schema,
        purchases: UnavailablePurchases(), foundationDiagnostics: inventory,
        additionalDiagnostics: engines
    )
}
```

RevenueCat uses `RevenueCatPurchases(key:configuration:)` and `RevenueCatProvider.diagnostics(publicKey:project:base:purchases:)`. iOS Firebase Analytics uses `FirebaseAnalyticsEngine(configuration:path:)` and `FirebaseProvider.diagnostics(googleServiceInfoPath:projectName:engine:base:)`, injected through `additionalAnalytics`. Other platforms have an unavailable Firebase Analytics adapter. The Live/Firebase umbrella products remain available for compatibility.

Pass each owned engine to its diagnostic builder so inventory can distinguish supplied configuration from runtime state. Passive builders can inspect configuration without starting an SDK. `base:` retains app expectations, build metadata, startup records, and custom inspections. Inventory metadata and successful construction do not prove provider ingestion, purchase verification, or remote resource provisioning.

Use resources belonging to the target app and account. Configure providers through tools authenticated to your own organization; this project does not supply provider accounts or a purchase catalog. Keep administrative credentials in an OS/tool credential store or CI secret store. Source-generation configuration accepts only public SDK configuration and safe project identifiers, never administrative tokens.

Firebase backend services such as Auth, Firestore, Functions, Messaging, and App Check remain app-owned. Review ownership of the default Firebase app and collection policy before integrating Analytics. Do not remove a backend dependency to satisfy a local telemetry isolation check.

### App-owned Firebase startup and Sentry privacy

Apps using Firebase App Check, Messaging or other backend services may initialize Firebase themselves, after installing their provider factories. Construct `FirebaseAnalyticsEngine(configuration: configuration, path: firebasePath, initialization: .reuseExistingDefaultApp)` only in a permitted runtime. This validates the already running default app against the supplied bundle/app/project identities and never initializes Firebase. Inject the engine through `LocalServices.make(additionalAnalytics:)`, and pass it to `FirebaseProvider.diagnostics(engine:)`. Analytics consent remains independent of backend startup. `managesAnalytics` indicates a valid Analytics binding; `ownsRunningSDK` remains false for reused apps. Replacement or identity changes block delivery and consent writes to the replacement. The default initialization mode still rejects an existing app.

For app-specific Sentry privacy, pass `eventFilter:` to `SentryDiagnostics`. Its `@Sendable (Event) -> Event?` callback runs synchronously on the delivery thread, after baseline PII removal; nil drops the event. The baseline user/request/extra removal runs again after the callback. Keep the filter stateless or thread-safe, never capture actor-isolated UI, and explicitly preserve any safe marker/correlation UUID needed for manual verification. Inject the engine through `additionalDiagnostics` and its passive provider builder. Do not initialize another Sentry SDK or replace telemetry preference gates.

Product event meaning, trigger points and domain-safe values belong to the app. Foundation validates the app-supplied schema and owns provider mapping, consent/runtime gates, counters and local sinks. Derive repeated allowlists from one app-owned definition. An adapter acceptance or submission is not backend ingestion.

## Optional setup tooling

The setup script changes a host app's project and writes generated bootstrap/build metadata files. Work on a reviewable branch, inspect the result, and build the affected targets. It performs local wiring; it does not create remote resources or publish the app.

From this repository root, prepare Python dependencies:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements.txt
```

Copy [config.example.json](config.example.json) into the host app as `.mzappfoundation/config.json`. Replace the project filename, target, bundle identifier, URL scheme, platform, deployment target, and event schema. The example has no providers or product catalog and disables remote delivery preferences. Set those preferences deliberately for your app. `bug_reporting: true` is supported only for iOS and requires microphone purpose text.

Run the supported modes, replacing the example app directory:

```sh
.venv/bin/python scripts/setup.py inspect --app-root ../MyApp
.venv/bin/python scripts/setup.py apply --app-root ../MyApp
.venv/bin/python scripts/setup.py verify --app-root ../MyApp
```

`--config` can select a different JSON file. The default config is under the app root, not this repository. Project and resource paths are app-root-relative; put a nested project specification's paths in that coordinate system. XcodeGen integration requires `xcodegen` on PATH. Native projects require Ruby and `bundle install --gemfile scripts/Gemfile`; run setup through the same Bundler environment (`BUNDLE_GEMFILE=scripts/Gemfile bundle exec .venv/bin/python ...`) if gems are not otherwise visible. The `RUBY` environment variable selects the Ruby executable.

`package_version` selects a release; the script default is `0.6.2`. To integrate this checkout instead, replace it with `package_path` pointing to the checkout root. An absolute local path avoids build working-directory ambiguity; keep machine-specific configuration out of shared examples. Setup retains compatibility generation for older explicit pins, so upgrading the package also requires reviewing generated code.

Supported provider fields are `revenuecat_public_key`, `sentry_dsn`, `google_service_info` (an app-relative plist path), `sentry_org`, `sentry_project`, `revenuecat_project_name`, `revenuecat_project_id`, `revenuecat_app_id`, `firebase_project_name`, and `sentry_project_id`. Provider products follow supplied SDK configuration. The `products` array is an inventory for review, not an instruction to invent or provision products. An empty catalog needs no offering creation.

Verification rejects unresolved direct vendor imports and checks generated wiring. Custom dependencies, xcconfigs, extensions, existing SDK initialization, and app entrypoint usage still need review. See [migration](migration.md) and the [setup skill](../skills/mz-app-foundation-setup/SKILL.md).

## Diagnostics and evidence

`VERSION` and the library lockfile generate `FoundationVersion.swift`. The app build phase writes `MZFoundationBuildMetadata.plist` with available source revisions, modified-tree flags, channel/date, and resolved package versions. Missing evidence remains unknown. Library lockfile metadata is separate from a runtime SDK version or backend verification.

`FoundationDiagnostics` supports provider expectations, expected identities, startup records, app-owned inspections, and manual verification actions. The last matching expectation wins. Telemetry counters and the bounded process-local timeline expose routing outcomes without retaining event payloads. Firebase/Sentry verification actions can supply correlation references for dashboard checks; submission is not ingestion confirmation.

`services.diagnosticExport()` produces a versioned JSON/text snapshot. UI and optional iOS report attachments let the user export it. Review app-owned inspection fields and exportable IDs for safe technical content. Neither a diagnostic snapshot nor a QA page proves production health. The QA page uses separate mock services and does not replace host services.

For network diagnostics, `InstrumentedSession(options: services.developerOptions).data(for:)` instruments that session only. Bodies, query values, credentials, raw error descriptions, and metrics are omitted. Paths must be safe to record; extend `RedactionPolicy` for app-specific sensitive keys.

For structured errors, pass the original error to `services.logger.error("Model loading failed", error: error, category: "model")`. Core `ErrorSnapshot` captures bounded causes and stack provenance without arbitrary localized descriptions or userInfo. App-authored messages still require privacy review. Error logs route through diagnostics once; warning logs stay local. Vendor formatting workarounds remain inside adapters.

See [verification](verification.md) for repeatable commands and [developer settings](developer-settings.md) for diagnostics UI APIs.
