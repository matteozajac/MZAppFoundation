# MZAppFoundation 0.5.0

Version 0.5.0 introduces reusable developer settings, independent optional provider products, and structured diagnostic evidence across iOS, visionOS, and macOS. These features are first published in 0.5.0. Existing apps remain on their chosen version until individually upgraded.

## Developer settings and platform presentation

`FoundationSettingsLink` opens protected navigation for provider details, build information, startup history, telemetry counters, session timeline, exports, access duration, links, and local QA scenarios. Developer access gates the entry and every destination; disabling or expiry dismisses open content. An issues filter shows provider/app-service warning and error findings.

Automatic presentation is an iOS sheet or a registered macOS/visionOS window with sidebar navigation. `FoundationSettingsScene` supplies the window, `.sheet` remains an explicit alternative, and macOS `FoundationSettingsCommands` provides Command–Option–D for settings and Command–Option–L for the console. App-owned `FoundationDeveloperPage` destinations can share this navigation. Optional local pages consolidate Pulse and iOS recording settings; macOS has a native searchable Pulse log view.

Developer UI copy stays English. This release does not add localization, a cross-app fleet dashboard, or watchOS/tvOS support.

## Optional providers and useful configuration evidence

New independent products are:

- `MZAppFoundationRevenueCat`: core and RevenueCat.
- `MZAppFoundationSentry`: core and Sentry.
- `MZAppFoundationFirebaseAnalytics`: core and Firebase Analytics on iOS.
- `MZAppFoundationUI`: core and SwiftUI with no vendor SDKs.

`MZAppFoundationLive` and `MZAppFoundationFirebase` retain compatibility composition APIs. `LocalServices.make` accepts additional analytics/diagnostics engines and an injected purchase provider. Empty engine arrays and explicit no-op engines support apps without remote providers; unavailable purchases grant no access. Root dependency resolution may still download unselected SDKs even when they are absent from the binary. The standalone `Packages/Core` core/UI package has no external dependencies.

Provider diagnostics separate configuration, runtime, delivery policy, SDK version provenance, expectations, and initialization ownership. Ordered requirements support required, optional, and intentionally unused providers per environment/platform, with the last matching rule winning. Known expected/supplied/running identifiers are compared; missing identity stays unknown. Firebase exposes its running project/app identifiers. RevenueCat/Sentry running dashboard identity remains unknown where the pinned public SDK APIs cannot establish it; ownership is tracked separately rather than inferred from an enabled flag.

SDK-free Firebase inspection shows a missing/unreadable/invalid `GoogleService-Info.plist`, missing required fields, and bundle-ID mismatch even without Firebase linkage. Safe project/app identifiers remain visible; keys and full DSNs do not. Structured startup records preserve the failed provider/stage, correction, partial initialization, runtime suppression, and recovery.

## Evidence, exports, and explicit checks

`VERSION` and the build metadata generator provide compiled foundation version/resolved-package metadata. An app build phase stamps optional source revisions, dirty flags, channel/date, and app lockfile versions into `MZFoundationBuildMetadata.plist`. Unstamped fields remain unknown; runtime SDK measurements are labeled separately.

Payload-free counters distinguish attempts, schema rejection, filtered properties, policy blocks, per-adapter acceptance, ignored records, and failures. Reasons/outcomes can overlap. The bounded process-local timeline defaults to 200 entries and reports evictions without retaining event payloads or arbitrary log text.

Versioned JSON/text exports include safe provider/build/startup context, counters, timeline, and cached purchase diagnostics. Custom typed service sections opt fields into export explicitly. Hosts can supply an immutable diagnostic capture to iOS bug reports; the form permits exclusion of `diagnostics.json`. Report attachments are shared deliberately and are not uploaded through analytics/Sentry.

RevenueCat diagnostics show offerings/products, entitlement verification, per-entitlement sandbox/production origin, expiration, and freshness timestamps without customer IDs, receipts, or transaction IDs. Explicit refresh follows normal entitlement verification and cannot purchase, restore, or override access rules. Firebase/Sentry tagged test-event actions require current runtime/delivery policy and return submitted UUID references for dashboard confirmation. SDK submission is not backend receipt, purchase verification, or Sentry symbolication.

## Shared access, routing, and safe QA

The shared preference spelling is `mzappfoundation.developer.enabled`, with migration from prior app-specific keys. Values remain scoped to the supplied defaults store. Session/timed access writes false for the next launch; saved choices persist. Access never changes telemetry permissions or purchase verification.

The standardized route is `mzappfoundation://<app-host>/developer/enable` or `/disable`. Unique app-scheme aliases use the same host/path, and legacy app routes remain accepted. The links page supplies copy/share, an enable-link QR code, and passive parsing with safe rejection reasons. Hosts cannot resolve OS ambiguity when multiple apps register the same custom scheme, so prefer unique app-scheme aliases.

Local QA uses a separate simulated composition for missing configuration, offline, pending purchase, and failed verification. It requires a local debug/simulator/test/preview runtime and never replaces live services or grants production access.

## Adopting 0.5.0

Setup defaults to `package_version: "0.5.0"`. Review the [example manifest](config.example.json), select the target app's actual providers, and follow [integration](integration.md) and [developer settings](developer-settings.md). Modern setup selects independent configured providers, registers the shared/app schemes, and installs build metadata generation. `package_path` remains available for local development.

Explicitly pinned 0.3.1 integrations retain their source-compatible generator path and umbrella products; new 0.5.0 APIs are not emitted into those apps. Upgrade each app deliberately and verify SDK isolation, configuration/identity, platform presentation, and its existing telemetry/purchase policy. Administrative credentials and provider ownership remain app-specific.

SDK pins remain Pulse 5.2.1, RevenueCat 5.88.0, Sentry 9.27.0, and Firebase 12.19.2. Supported platforms remain iOS 26, visionOS 26, and macOS 15. See the [validation record](developer-settings-validation.md) for exact automated evidence and the separate limits around physical devices, provider ingestion, purchase/restore, archive symbols, and signing. Publishing this package does not provision providers, distribute consuming apps, or migrate another app automatically.
