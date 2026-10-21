# MZAppFoundation 0.5.1

Version 0.5.1 makes the developer console accessible from a keyboard and above existing iOS sheets or alerts. It also provides shared keyboard help, short app-specific developer links, and consistent Ladybug report access from Foundation settings.

## Keyboard help and access

Command–D opens the developer console while developer mode is enabled. iOS uses a responder container around the scene's existing root controller, preserving the SwiftUI view tree, environment, text fields and ordinary keyboard actions. macOS `FoundationSettingsCommands` uses Command–D, retains Option–Command–L, and opens Foundation settings with Control–Option–Command–D. visionOS installs Command–D on the app's developer-tools modifier.

`FoundationKeyboardShortcutsLink` and `FoundationKeyboardShortcutsView` provide reusable help in ordinary app settings. `FoundationSettingsView` also includes this destination, and macOS has a Help menu entry. Apps inject `FoundationKeyboardShortcutSection` values to document their own implemented actions. Help remains readable when developer mode is disabled and labels protected shortcuts unavailable.

## Console presentation and reports

Both console-only and reporting-enabled iOS apps use a temporary window in the originating scene. Existing sheets, alerts and unfinished app state remain attached to the app window. Dismissing tools restores that window's focus. No permanent key window, global responder override or method swizzling is installed.

Reporting-aware Foundation console and recording pages share the same `DeveloperReporting` instance and Ladybug action. Reporting retains the existing bounded 60-second silent ReplayKit buffer, screenshot, Pulse export, optional voice narration, diagnostics and schema-2 ZIP format. Developer-mode revocation closes tools, waits for pending exports before deleting files, and prevents stale asynchronous work from presenting another report.

## Short developer links

The routes are `<app-scheme>://developer/enable` and `<app-scheme>://developer/disable`, for example `bedtimestories://developer/enable`. Bundle identifiers are absent. Use `DeveloperDeepLink.url(for:scheme:)`; older host-parameter overloads remain source compatible and produce the same short route when supplied an app-specific `scheme:`. Their retired shared-scheme default returns `nil`.

Shared `mzappfoundation` links and older long routes are rejected. Apple documents that a shared custom scheme has an undefined target when multiple apps register it; it does not provide reliable app selection. Current setup removes that shared registration and preserves unrelated schemes. [Apple custom URL scheme documentation](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)

Setup defaults to 0.5.1. Explicit older pins retain compatible generation until individually upgraded. SDK pins and deployment targets are unchanged: Pulse 5.2.1, RevenueCat 5.88.0, Sentry 9.27.0, Firebase 12.19.2; iOS/visionOS 26 and macOS 15. Existing host apps retain their integrations until explicitly migrated.

See [validation](developer-tools-0.5.1-validation.md), [integration](integration.md), and [developer settings](developer-settings.md). Physical keyboard, accelerometer, ReplayKit and microphone acceptance remain separate from simulator/build evidence.
