# Migrating an existing app

Adopt the package in one app at a time. Keep the app's behavior, privacy policy, purchase rules, backend ownership, and release process explicit throughout the change. This guide describes a workflow; it does not certify a migration or authorize remote provisioning.

## Inventory before editing

Record the app's supported platforms and deployment targets, pinned dependencies, entrypoints, build configurations, and test targets. This checkout requires Swift 6.2, iOS/visionOS 26, or macOS 15. Resolve a lower deployment target or conflicting vendor pin before integrating.

Find existing analytics, diagnostics, logging, purchase, and Firebase initialization. Note network instrumentation, redaction rules, user identity binding, persisted preferences, custom URL schemes, developer access, and report attachments. Separate Firebase Analytics ownership from app-owned Auth/Firestore/Functions/App Check or other backend features.

Document the current event allowlist, remote delivery defaults, purchase/restore semantics, and handling of pending, offline, revoked, or unverifiable entitlements. Account for extensions, companion apps, background work, and multiple windows. These contracts remain app-owned.

## Migrate in small steps

1. Adapt app events and domain protocols to `AnalyticsEvent`, `TelemetryValue`, `PurchaseProviding`, and other core interfaces. Keep feature behavior and presentation independent of SDKs.
2. Build a single app-lifetime composition. Start with local or injected test engines; explicitly use `UnavailablePurchases` when no real purchase provider is configured. Use `MockPurchases` only for declared simulations.
3. Replace initialization and fan-out deliberately. Remove competing ownership of vendor singletons only after confirming no remaining app feature needs it. Keep identity binding and sign-out behavior consistent with the host app.
4. Carry over the app's existing delivery preferences. A package initializer's default is not permission to enable analytics or diagnostics in a migrated app. Preserve consent persistence and revocation behavior.
5. Remove duplicate package references only after tracing every consumer. A backend SDK still required by the app is a residual dependency to document, not a reason to delete backend functionality.
6. Review generated project changes and wire the entrypoint and scenes. Run static verification, build/test affected targets, inspect local binaries, then perform the device and provider checks relevant to the app.

Use the [integration guide](integration.md) for composition and optional setup commands. Setup can modify build configurations, dependencies, URL registrations, generated Info.plist values, and build phases. Review custom xcconfigs, target dependencies, script phases, synchronized groups, and extensions rather than assuming generated verification covers them.

## Developer access and links

The current preference key is `mzappfoundation.developer.enabled`, scoped to the supplied defaults store. `DeveloperOptions(configuration:defaults:legacyPreferenceKeys:)` supports deliberate migration of older app-specific preference keys. Preserve a user's explicit saved off choice.

Choose the app's unique registered URL scheme and preserve unrelated handlers. Current links use `myapp://developer/enable` and `myapp://developer/disable`. Older shared-scheme and long routes should not be retained as competing entrypoints. Check settings navigation, keyboard actions, sheets, and multi-window presentation in the host app. Developer access controls tools, not telemetry permission or purchase access.

## Replacing an existing iOS reporter

The reporting module provides a rolling silent screen cache, screenshot, optional voice note, report ZIP, and native share UI. The Pulse attachment adapter lives in `MZAppFoundationLocal`. Reuse one reporting instance for both the tools modifier and settings pages:

```swift
#if os(iOS)
import MZAppFoundation
import MZAppFoundationLocal

@MainActor
func migratedReporting(services: AppServices) -> DeveloperReporting {
    DeveloperReporting(
        services: services,
        archivePrefix: "myapp",
        preferenceKey: "com.example.myapp.recordRecentActivity"
    )
}
#endif
```

Replace the example prefix and preference key with the existing app's values if preserving filenames or a saved recording choice matters. Pass this instance to `.appDeveloperTools(services.developerOptions, reporting: reporting)` and `FoundationDeveloperTools.pages(services: services, reporting: reporting)`. A generated `MZBootstrap.reporting` may supply that instance instead; do not create both.

Replace a legacy global shake override when adopting the scoped modifier, and preserve an accurate microphone purpose string and appropriate build/access gates. Keep the app's Pulse network exclusions, store selection, and attachment policy. Sharing the same store exports that configuration's logs; the reporter does not recreate host instrumentation or automatically upload reports.

Compare the old reporter's minimum OS, dependencies, recording format, consent/defaults, and archive schema. Capture and microphone behavior need separate device validation; compilation alone cannot establish parity.

## Migration acceptance

Use [verification](verification.md) to select checks. Record separately what was established by source review, unit tests, simulator UI, binary inspection, physical hardware, and provider dashboards. Include exact app/package revisions and unresolved dependencies. A successful local build does not prove real purchase/restore, remote ingestion, symbolication, report delivery, or a release.
