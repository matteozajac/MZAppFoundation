# Foundation developer settings

Version **0.5.1** supplies a protected **App Foundation** entry with separate provider, build, startup, telemetry, export, access, keyboard help, and QA pages. iOS uses a navigation stack in a sheet; macOS and visionOS use a dedicated window with a sidebar. An **Only show provider issues** filter shows providers and app-owned services with warning/error findings. Disabling or expiring developer access removes the entry and dismisses open foundation content, including custom destinations.

Developer settings and independent provider products were introduced in 0.5.0. Version 0.5.1 adds shared keyboard help, Command–D console access, presentation above existing iOS sheets/alerts, and short app-specific developer links. Other apps retain their current integrations until individually upgraded. The developer UI remains in English. See [0.5.0 release notes](release-0.5.0.md) for the earlier provider/settings release.

## Add the component

The local and compatibility compositions re-export the UI module. The separate `MZAppFoundationUI` product, also available from `Packages/Core`, depends only on the SDK-free core.

For iOS screen recording and ZIP reports, enable `bug_reporting: true` in setup configuration and use the generated app-lifetime `MZBootstrap.reporting`. Supply the same instance to the settings pages and primary-window modifier. The reporting-aware Pulse entry opens the console with its Ladybug report action; recording settings expose the saved preference, capture status and retry action.

```swift
import MZAppFoundationLocal

Form {
    #if os(iOS)
    FoundationSettingsLink(
        services: services,
        pages: FoundationDeveloperTools.pages(services: services, reporting: MZBootstrap.reporting)
    )
    #else
    FoundationSettingsLink(
        services: services,
        pages: FoundationDeveloperTools.pages(services: services)
    )
    #endif
}
```

Keep `.appDeveloperTools(services.developerOptions, reporting: MZBootstrap.reporting)` on the primary iOS app window for incoming URLs, shake/Command–D console access and recording lifecycle. The console uses a separate window in the originating scene, so it can appear above an existing sheet or alert. Closing it restores the original window and preserves the app's previous presentation. For manual composition, create one `DeveloperReporting(services: services)` beside the shared services instead of using generated bootstrap. The host must provide `NSMicrophoneUsageDescription` for voice narration. See [bug reporting](bug-reporting.md) for capture, sharing and permission behavior.

Reporting is optional and iOS-only. Apps retaining console-only behavior use `FoundationDeveloperTools.pages(services:)` and `.appDeveloperTools(services.developerOptions)` on every supported platform. On macOS and visionOS, automatic presentation requires the matching scene beside the app's primary `WindowGroup`:

```swift
#if os(macOS) || os(visionOS)
FoundationSettingsScene(
    services: services,
    pages: FoundationDeveloperTools.pages(services: services)
)
#if os(macOS)
    .commands { FoundationSettingsCommands(services: services) }
#endif
#endif
```

The macOS Developer menu opens the console with **Command–D** or its **Option–Command–L** alias. **Control–Option–Command–D** opens App Foundation settings; adding Control avoids the system's Option–Command–D Dock shortcut. The Help menu includes **Keyboard Shortcuts**. Settings and help windows do not launch automatically or restore after relaunch. Register `DeveloperConsoleScene(options:)` separately when using the console window. On macOS, the package presents a native searchable view of the latest 500 local Pulse log messages; Pulse's public `ConsoleView` is unavailable there. On iOS and visionOS, the composed console page uses PulseUI.

Use `presentation: .sheet` on `FoundationSettingsLink` to opt into sheet presentation on macOS/visionOS without registering a settings scene. iOS always uses a sheet. `FoundationSettingsView(services:pages:)` is available for app-owned presentation. Multi-window apps should pick their primary presentation owner.

Opening a page or capturing a snapshot performs passive inspection. It does not initialize an SDK, request customer information/offerings, start recording or network capture, purchase, or restore. The provider pages expose separate, explicit manual actions where an adapter supplies them.

## Keyboard help and app shortcuts

`FoundationKeyboardShortcutsLink(options:sections:)` adds a **Keyboard Shortcuts** entry to any app settings `List` or `Form`. It remains available with developer mode off; protected developer shortcuts are marked inactive. The App Foundation navigation also contains the same help page. The foundation supplies the help UI, accessible key names, and built-in shortcut catalog; apps inject their feature descriptions through `FoundationKeyboardShortcutSection` and `FoundationKeyboardShortcut`.

```swift
let previousPage = FoundationKeyboardShortcut(
    id: "reader.previous", title: "Previous page", key: .leftArrow, modifiers: []
)
let readerShortcuts = [
    FoundationKeyboardShortcutSection(id: "reader", title: "Reading", shortcuts: [
        previousPage,
        .init(id: "reader.next", title: "Next page", key: .rightArrow, modifiers: [])
    ])
]

Form {
    FoundationKeyboardShortcutsLink(options: services.developerOptions, sections: readerShortcuts)
    FoundationSettingsLink(services: services, keyboardShortcutSections: readerShortcuts)
}

// The app installs the action using the same shortcut definition as its help entry.
Button("Previous page", action: goToPreviousPage)
    .keyboardShortcut(previousPage.shortcut)
```

Help entries describe bindings; injecting a section does not install feature actions. The app owns reader actions and their availability. Keep shortcut/section IDs stable and unique; foundation entries win when an injected ID repeats, and empty sections are omitted. Hold Command on iPad or visionOS to view the system's shortcuts for the current screen.

`FoundationSettingsLink`, `FoundationSettingsView`, and `FoundationSettingsScene` accept `keyboardShortcutSections:`. Pass the same app sections to each presentation owner. On macOS/visionOS, `FoundationSettingsScene` also registers the help window; `FoundationKeyboardShortcutsScene(options:sections:)` can be registered independently when the app only needs help. Use `presentation: .sheet` on the help link to avoid a separate window, or embed `FoundationKeyboardShortcutsView(options:sections:)` in app-owned navigation.

Command–D requires developer mode and opens the same console as shake or `requestConsole()`. It never enables developer mode. On iOS, `.appDeveloperTools` installs the keyboard and shake responder; on macOS, register `FoundationSettingsCommands` along with the console scene. Use `FoundationKeyboardShortcutCatalog` when referring to package-owned bindings.

## Optional SDK products

| Product | Composition |
| --- | --- |
| `MZAppFoundationUI` | Core and SwiftUI, no vendor SDKs |
| `MZAppFoundation` | Core, UI, Pulse local composition; optional iOS reporting integration |
| `MZAppFoundationRevenueCat` | Core and RevenueCat only |
| `MZAppFoundationSentry` | Core and Sentry only |
| `MZAppFoundationFirebaseAnalytics` | Core and Firebase Analytics on iOS; passive unsupported-platform diagnostics elsewhere |
| `MZAppFoundationLive` | Compatibility umbrella: local composition, RevenueCat, Sentry |
| `MZAppFoundationFirebase` | Compatibility umbrella: Live plus iOS Firebase Analytics |

The independent products let an app link only its selected SDKs. The existing umbrellas retain their factory/import APIs. Root-package dependencies can still be resolved/downloaded even when an unselected SDK is absent from the binary. Use `Packages/Core` when dependency resolution must also stay vendor-free. See [integration](integration.md) for injected engine composition.

Absent providers need no SDK. Empty telemetry engine arrays work, and `NoopAnalyticsEngine` / `NoopDiagnosticsEngine` provide explicit inert implementations. `UnavailablePurchases` throws `PurchaseFailure.unavailable` and grants no access. `MockPurchases` is a deliberate simulated choice; generated device compositions start with unavailable purchases until a real adapter is created.

## Provider expectations and identity

Each provider independently reports SDK linkage/version, supplied configuration, runtime state, delivery policy, expected usage, and initialization ownership. A configured provider can remain uninitialized because delivery is disabled. A simulator can display valid configuration while runtime safety blocks initialization. Configuration and SDK submission do not prove backend receipt.

Declare required, optional, or intentionally unused providers per app environment and platform. Rules are evaluated in order: the **last matching** `ProviderRequirement` wins; unmatched providers default to optional.

```swift
var inventory = FoundationDiagnostics(
    expectations: [
        .init(.firebase, expectation: .optional),
        .init(.firebase, expectation: .required,
              environments: [.internalTesting, .production], platforms: [.iOS]),
        .init(.firebase, expectation: .intentionallyUnused, platforms: [.visionOS, .macOS]),
        .init(.revenueCat, expectation: .intentionallyUnused)
    ],
    expectedIdentities: [
        .firebase: .init(projectID: "my-app-prod", appID: "1:123:ios:abc")
    ]
)
```

Missing/invalid required configuration and unsupported/unlinked required adapters produce findings with correction steps. An intentionally unused provider that is present produces a warning. The issues filter uses warning/error findings rather than treating every absent optional SDK as broken.

Identity is separated into **expected** (the app's declared target), **supplied** (configuration and app-owned labels), and **running** (what a supported public SDK API can establish). Known project/app/organization identifiers are compared; missing fields are never treated as a match. Display names are labels, not proof of remote project identity.

Firebase reads running project/app identifiers from `FirebaseApp` options. The pinned RevenueCat and Sentry SDKs do not expose a supported running dashboard-project accessor, so that identity stays unknown. Adapter bootstrap tracking separately reports ownership by this composition, external initialization, not initialized, or unknown. A global SDK-enabled flag alone cannot establish ownership. The app must retain one SDK bootstrap owner; arbitrary later direct SDK replacement is outside the supported composition contract.

RevenueCat/Sentry configuration accepts optional `ProviderProjectIdentity` labels. Sentry additionally derives its safe ingestion host and numeric project ID from a valid DSN and flags disagreement with the app's declared project ID. Full DSNs and SDK keys remain hidden. Expected identity comes from app-owned declarations; this screen does not call administrative APIs to verify them.

## Firebase configuration

Apple apps use `GoogleService-Info.plist`; Android uses `google-services.json`. The SDK-free inspector distinguishes an absent file, a supplied path that no longer exists, an unreadable/malformed plist, missing required fields, and a bundle-ID mismatch—even when Firebase is not linked. It exposes only project ID, Google app ID, configured bundle ID, sender ID, and storage bucket. `API_KEY` and arbitrary plist fields never enter diagnostics. [Firebase Apple setup](https://firebase.google.com/docs/ios/setup)

The package supplies Firebase Analytics on **iOS only**. UI and passive file inspection work on macOS/visionOS without claiming Analytics support. A plist does not prove a Firebase–Google Analytics property link or event ingestion.

Supply `projectName:` to `FirebaseProvider.diagnostics`, or `firebaseProjectName:` to compatibility `FirebaseServices.make` / `makeRecovering`, for an app-owned display label beside authoritative plist identifiers. The default core inspection also exposes supplied identity for comparison when the SDK is absent.

## Build metadata and startup history

`VERSION` is the foundation version source. `scripts/generate_build_metadata.py` generates `FoundationVersion.swift` from `VERSION` and the library's `Package.resolved`:

```sh
python3 scripts/generate_build_metadata.py \
  --foundation-root "$PWD" \
  --foundation-swift-output Packages/Core/Sources/MZAppFoundation/FoundationVersion.swift
```

The app's build phase separately writes `MZFoundationBuildMetadata.plist` into the built bundle. It can stamp app/foundation Git revisions, modified-working-tree flags, build channel/date, and resolved package versions. App-side `Package.resolved` takes precedence over the library snapshot. `SOURCE_DATE_EPOCH` or `--timestamp` can provide a reproducible date; `--stamp-build-time` supplies the current build time when no explicit timestamp is present. Setup copies the generator and adds this build phase for 0.5.0+ integrations or a current local checkout.

Without a bundle stamp, `FoundationBuildMetadata.current()` labels the library snapshot and leaves unknown app fields unstamped. A Git revision with a modified-working-tree flag does not identify all uncommitted source changes. Runtime measurements stay separate: RevenueCat reports `Purchases.frameworkVersion`, FirebaseCore reports `FirebaseVersion()`, and Sentry/FirebaseAnalytics display generated resolved-version metadata with explicit provenance. An absent adapter asserts no runtime SDK version.

Startup history contains typed provider, stage, status, stable code, safe explanation, correction, and timestamp records. Validation, adapter construction, initialization conflicts, runtime suppression, and local recovery remain distinct. An adapter-ready record does not claim an SDK has already activated. Compatibility `make` factories retain throwing behavior; `makeRecovering` preserves which provider failed and any partial startup evidence while providing local telemetry and unavailable purchases. Generated independent compositions can preserve working providers when another adapter fails.

## Telemetry counters and session timeline

Counters cover public attempts, schema rejection, filtered properties, preference/runtime blocking, absence of engines, local records, remote-adapter acceptance, breadcrumb submissions, ignored records, and failures. Analytics, diagnostics, and breadcrumbs have separate counters. Attempts count calls; outcomes count each adapter. Multiple adapters and overlapping blocking reasons mean the columns are **not** a partition of attempts. A recorded adapter result or submitted breadcrumb does not prove delivery. The screen can reset counters without changing preferences.

The timeline stores only closed event/category/status vocabularies, optional provider, UUID, and timestamp. It contains no event payloads, URLs, customer identifiers, or arbitrary log messages. It is process-local and does not persist or upload itself. Capacity defaults to 200, is clamped to 1–1,000, and reports discarded entries when older entries are evicted. The timeline page can clear this local history.

## Purchase details and manual verification

RevenueCat's passive cache shows received offerings, products/packages, current offering, active/inactive entitlements, per-entitlement sandbox/production origin, verification outcome, expiration, CustomerInfo request date, receive time, and last offerings response time. A customer may have both sandbox and production entitlements; there is no single asserted customer environment. SDK responses can be cached, and receive time is not proof of a fresh server request. No customer ID, receipt, token, or transaction ID appears in these diagnostics. [CustomerInfo](https://www.revenuecat.com/docs/customers/customer-info), [SDK caching](https://www.revenuecat.com/docs/test-and-launch/debugging/caching)

**Refresh customer information and offerings** performs an explicit read-only provider request. CustomerInfo uses the current-fetch policy; offerings may still come from SDK cache. A successful response confirms that data was received, not that a purchase or App Store catalog is verified. The refresh updates normal CustomerInfo state using the existing entitlement verification rules; it cannot override verification, purchase, or restore. Identity/ownership is checked after asynchronous responses so stale or competing SDK state is rejected.

Firebase and Sentry offer explicit tagged event submission actions. They require this composition's adapter, a runtime permitting remote delivery, and the applicable current analytics/diagnostics preference. Sentry sends a non-crashing informational event. Both return **submitted**, with a generated UUID correlation reference; they never claim backend confirmation. Check that reference in the provider dashboard. Firebase DebugView additionally requires the SDK's debug mode. [Firebase DebugView](https://firebase.google.com/docs/analytics/debugview)

Ordinary inspection never runs these actions. Manual outcomes are visible in the provider page and represented by typed events in the session timeline.

## Export and bug reports

`services.diagnosticExport()` captures an immutable `FoundationDiagnosticExport`; `.jsonData()` produces sorted, versioned JSON (`format: mzappfoundation-diagnostics`, `schemaVersion: 1`) with a 1 MiB limit, and `.text` supplies a readable summary. The export page can save JSON/text, copy text, or share text.

The export includes safe build context, provider expectations/identity/findings, startup codes, preferences/developer access, counters, bounded timeline, cached purchase diagnostics, and explicitly selected custom fields. It excludes raw logs, event payloads, SDK keys, DSNs, credentials, user/customer IDs, receipts, transaction IDs, and pasted links. Free-form provider/startup explanations are replaced with safe summaries/codes; exported custom values pass a separate safety filter. An app must still supply audited technical labels, identifiers, and finding codes.

On iOS, the host opts into a `diagnostics.json` ZIP attachment by constructing `DeveloperReporting(services: services)` or providing its `diagnostics:` capture closure. One immutable snapshot is captured when reporting begins. When a capture is supplied, inclusion defaults on and the report form lets the user exclude it; unavailable captures are recorded separately from exclusions. Sharing remains a deliberate local report action and does not send the attachment through analytics/Sentry. The reporting module itself has no SDK/core dependency. See [bug reporting](bug-reporting.md).

## App-owned diagnostics and pages

Use typed service inspections for app-specific CloudKit, authentication, push, sync, model/download, or other configuration. They have their own navigation destinations and findings. Field export is opt-in per identifier:

```swift
inventory.additionalInspections = [
    FoundationDiagnosticInspection(id: "sync") { context in
        FoundationDiagnosticSection(
            id: "sync", title: "Sync", summary: "App-owned sync configuration",
            details: [.init("environment", label: "Environment",
                            value: context.configuration.environment.rawValue)],
            exportableDetailIDs: ["environment"]
        )
    }
]
```

Inspection closures must remain passive and expose safe technical configuration. User content and authentication credentials do not belong here. Duplicate service/page IDs are de-duplicated; keep IDs stable.

For an interactive tool, provide a SwiftUI destination:

```swift
let pages = [
    FoundationDeveloperPage(id: "sync.tools", title: "Sync tools", systemImage: "arrow.triangle.2.circlepath") {
        MySyncDeveloperView()
    }
]
```

Pass the same pages to the link and registered settings scene. The foundation gates access and navigation; the app remains responsible for any operation inside its page. `FoundationDeveloperTools.pages` optionally consolidates Pulse and, on iOS with a supplied `DeveloperReporting`, recording settings into this navigation without adding those dependencies to the SDK-free UI product.

## Developer access and app links

`DeveloperOptions.preferenceKey` is `mzappfoundation.developer.enabled` on every supported platform. Its spelling is shared; its value lives in the supplied app defaults store. Apple app sandboxes do not synchronize a value merely because the key has the same name.

Migration checks `<bundleIdentifier>.developer.enabled` and optional `legacyPreferenceKeys`, including an explicit false. The canonical key wins; legacy values are retained. Local/Internal defaults on, production defaults off, and saved choices override defaults. The page shows activation from app default, saved choice, migration, link, manual choice, or session.

`setEnabled` and enable/disable links save a choice. `enableUntilAppCloses()` and `enable(for:)` replace saved access with **false for the next launch**, then enable only this process/session. This also overrides development defaults after relaunch. Timed access uses a monotonic deadline; its date is display-only. Expiry revokes capture, dismisses foundation content, and is refreshed when the app becomes active. The UI offers session, 15-minute, 1-hour, persistent, and disable choices. Temporary access never changes purchase access or telemetry preferences.

The URL contract uses the app's registered unique scheme:

```text
myapp://developer/enable
myapp://developer/disable
```

Register the app's `AppConfiguration.urlScheme` in `CFBundleURLTypes`; the links page checks the actual bundle registration. URLs contain no bundle identifier. Generate them with `DeveloperDeepLink.url(for: .enable, scheme: configuration.urlScheme)` and inspect them with `DeveloperDeepLink.inspect(input, scheme: configuration.urlScheme)`. Only the exact `developer` host and `/enable` or `/disable` route are accepted for that app's scheme.

Version 0.5.1 removes the shared `mzappfoundation` enable link and its registration from current setup. Apple states that the target app is undefined when multiple apps register the same scheme; it provides no app-selection guarantee. A bundle-ID host cannot make that scheme choose the intended app. Current routing rejects both shared-scheme URLs and the former long app/bundle-ID-host routes. The older host parameters remain source-compatible but do not affect current URLs. [Apple custom-scheme routing](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)

The links page provides copy/share actions and an enable-link QR code, plus `DeveloperDeepLink.inspect` as a dry run with safe acceptance/rejection reasons. Inspection neither opens a URL nor changes access and never exports pasted text. Credentials, ports, queries, fragments, encoded host/path alternatives, wrong hosts, and unsupported routes are rejected.

## Local QA scenarios

The QA page builds a **separate simulated composition** for missing configuration, offline networking, pending purchase, and failed verification. It does not replace the host's services or initialize/contact any live SDK. Pending/failed verification scenarios grant no entitlement.

`DeveloperQAServices` requires a local environment and a supported debug/simulator/test/preview runtime; production/Internal environments are rejected. Enabling developer options alone cannot bypass this check. Package build flags must not be inferred from app flags. The sample accepts `--foundation-qa missing-configuration|offline|pending-purchase|verification-failed`; these are sample launch arguments, not globally interpreted production overrides.

## Setup and verification

Setup defaults to **0.5.1**. For 0.5.1+ or a current local checkout, it registers only the app's unique scheme and removes earlier shared-scheme entries while preserving unrelated URL types. Independent products and the build metadata phase were introduced in 0.5.0; products are selected only for configured providers. `package_path` remains available for local development. Explicitly pinned older integrations retain compatible generation and do not receive newer APIs until upgraded.

Safe metadata fields include `revenuecat_project_name`, `revenuecat_project_id`, `revenuecat_app_id`, `firebase_project_name`, and `sentry_project_id`, alongside `sentry_org` / `sentry_project`. Client configuration belongs to the target app. Administrative credentials are never generated into the app or diagnostics.

The package supports iOS 26, visionOS 26, and macOS 15. It uses system text sizes, selectable values, accessible status labels, compact navigation, and desktop/spatial sidebars. watchOS/tvOS support is not added. Automated builds/tests are separate from physical-device acceptance, backend ingestion, purchase/restore, symbol uploads, archive/signing, and app migrations. See [the dated validation record](developer-settings-validation.md) for current evidence and outstanding checks.
