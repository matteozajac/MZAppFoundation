# Adopting existing apps

No existing app was migrated in the initial delivery. Perform one app migration at a time with its own behavior checks and release policy.

- **TwinGlyph:** retain game-specific access rules and `TwinGlyphPurchaseService` presentation/recovery policy; replace its provider with the shared purchases interface. Map `full_access` explicitly. Preserve its URL scheme, and migrate the existing developer preference key deliberately. Public Pulse inclusion changes its current binary policy. Keep RealityKit/Crown and Game Center outside this package.
- **Masseter:** retain typed event schemas and channel-specific preferences; replace provider implementations and composition. Do not move health/private data into generic metadata. Its watch telemetry relay remains app-owned.
- **Second Take:** preserve its off-by-default analytics and diagnostics policy and restricted technical event vocabulary. Do not enable automatic crash reporting merely because the package's new-app default permits it: use a diagnostics adapter/policy matching the app's approved contract before migration. Rehearsal text never enters logs. Ads and purchase access rules remain app-owned.
- **Roamline:** retain analytics privacy allowlists, structured categories and app-specific network redaction. Move Pulse setup and provider fan-out into the package; preserve watch/phone and playback behavior. Keep existing archive symbol verification requirements until shared verification proves equivalent.
- **JoinOurDay:** preserve backend Firebase initialization for Auth/Firestore/Functions/App Check, and existing billing identity binding. The package owns Analytics only. Reconcile singleton ownership and remove direct SDK calls from the local target. Preserve existing deep-link handling and keep work within the JoinOurDay team.

Migrate by adapting app events and domain protocols to package-owned values first, replacing initialization second, removing duplicate package dependencies third, then proving local binary isolation and device behavior. Never remove an SDK dependency still required by an app-owned backend feature just to make an audit pass. Report that residual dependency precisely.

## JoinOurDay bug reporting

JoinOurDay's local `Packages/BugReporter` capture, rolling cache, screenshot, voice narration and ZIP logic already exists in `MZAppFoundationReporting`; the Pulse adapter lives in `MZAppFoundationLocal`. A future migration should keep one shared reporter and route both shake/console access and foundation settings through it. This manual instance replaces use of a generated reporter:

```swift
import MZAppFoundationLocal

@MainActor enum AppInfrastructure {
    static let services = MZBootstrap.services
    static let reporting = DeveloperReporting(
        services: services,
        archivePrefix: "jod-ios",
        preferenceKey: "BugReporter.recordRecentActivity"
    )
}
```

Use `.appDeveloperTools(AppInfrastructure.services.developerOptions, reporting: AppInfrastructure.reporting)` on the primary iOS window and `FoundationDeveloperTools.pages(services: AppInfrastructure.services, reporting: AppInfrastructure.reporting)` for its settings. Retaining the `jod-ios` prefix preserves existing report names; retaining the legacy recording key preserves an explicit saved off choice. Replace the app's global `UIWindow` shake override when adopting the scoped modifier, and preserve the existing microphone purpose text and QA build gates.

Log capture and exclusions remain host-owned. Preserve JoinOurDay's existing Pulse network instrumentation, excluded hosts and logging policy when replacing its attachment adapter. Reporting exports the supplied store; it does not recreate that host configuration or automatically upload reports.

Resolve deployment and dependency differences before changing the app: JoinOurDay's local reporter targets iOS 18.2 and pins Pulse 5.2.3, while the Foundation root package requires iOS 26 and pins Pulse 5.2.1 for its supported platforms. Choose compatible app/package targets and one Pulse version deliberately, then validate affected platforms and physical-device recording behavior. These notes do not migrate JoinOurDay or change either package's deployment target or pin.
