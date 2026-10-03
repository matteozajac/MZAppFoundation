# Developer settings validation — 2026-10-03

Environment: Xcode 27.0 (`27A266a`), Swift 6 language mode, macOS host. Work remained on `main`. The implementation checks below were collected with the pre-release `0.4.0-dev` version label before preparing **0.5.0**; release-version checks are recorded separately below. Scope includes the selected ideas 1–15 and the platform presentation and issues filter from 17; fleet auditing and new localization were excluded as requested.

| Check | Result | Evidence |
| --- | --- | --- |
| SDK-free core, migration, deep links, temporary access, requirements, identity, QA, export privacy, counters and timeline | 50 tests in 8 suites passed | `output/developer-settings-v2/core-tests-current.log` |
| Setup generation, independent products, old-version compatibility, repeat-run preservation and `MZ_LOCAL` configurations | 14 tests passed | `output/developer-settings/setup-tests-expanded.log` |
| Reproducible build metadata, safe provenance and resolved dependencies | 5 tests passed | `output/developer-settings-v2/build-metadata-tests-final.log` |
| Live/Firebase provider inspections, identity checks, purchase diagnostics, startup validation, delivery guards and logging adapters | 8 tests passed on iOS 26 simulator | `output/developer-settings/ProviderExpansionDone.xcresult` |
| Reporting, ZIP attachment selection, privacy and existing recording lifecycle | Full 33-test suite passed, followed by 3 focused diagnostics tests covering core-export interoperability and validation | `output/developer-settings-v2/ReportingTests.xcresult`, `ReportingDiagnosticsVerified.xcresult` |
| Report inspector and Mac transcription helpers | 24 inspector tests and 9 transcription tests passed | `output/developer-settings-v2/report-inspector-tests-final.log`, `report-transcription-tests-final.log` |
| iOS settings navigation and developer access; required-provider findings, custom services, counters/export; deep-link dry run and isolated pending purchase; bug reporting with diagnostics | All 4 UI scenarios passed on iPhone 18 Pro / iOS 27 | `output/developer-settings-v2/SettingsUIVerified.xcresult`, `settings-ui-verified.log` |
| Final pending-purchase QA presentation | Focused UI scenario passed; no active entitlements displayed explicitly as `None` | `output/developer-settings-v2/QAUIFinal.xcresult`, `qa-ui-final.log` |
| iOS Internal device composition | Build succeeded without signing | `output/developer-settings-v2/ios-device-current.log` |
| visionOS Internal device composition | Build succeeded without signing | `output/developer-settings-v2/vision-device-current.log` |
| Setup-generated app with independent providers and stamped metadata | Internal iOS build succeeded without signing; metadata read back | `output/developer-settings/setup-generated-ios-build-expanded.log` |
| Optional SDK linkage | Firebase-only, RevenueCat-only and Sentry-only Release apps contain their selected SDK, with the other provider SDKs and Pulse absent | `output/developer-settings/provider-isolation-audit.json` |
| Local iOS binary isolation | Pulse present; RevenueCat, Sentry, Firebase/GoogleAppMeasurement absent | `output/developer-settings-v2/local-binary-audit.json` |
| Native macOS sample | Ad-hoc signed build succeeded; native interaction checks cover settings/sidebar, missing Firebase, console, commands and developer revocation | `output/developer-settings-v2/mac-ui-final-signed-build.log`, `mac-native-validation.md` |
| Patch whitespace and branch | Passed; `main` | `git diff --check`, `git branch --show-current` |

The final iOS screenshots were exported from the passing results and visually inspected. They are retained under `output/developer-settings-v2/`: `overview.png`, `firebase-missing.png`, `required-firebase.png`, `diagnostics-export.png`, `qa-pending.png` and `bug-report-diagnostics.png`. The attachment manifests are `ScreenshotsVerified/manifest.json` and `QAUIFinalScreenshots/manifest.json`; the latter supplies the final QA screenshot. The final Mac SwiftUI module also compiled after this QA text correction (`mac-core-ui-build-final.log`).

The expanded UI tests caught an iOS navigation regression caused by using selection-based lists in the sheet. iOS now uses ordinary navigation links; macOS and visionOS retain selection-based sidebars. The final four-scenario run uses the built XCTest bundle directly, avoiding package re-resolution during execution.

macOS XCTest did not execute test cases successfully on this host. The unsigned runner was rejected by Gatekeeper; a cached ad-hoc runner was killed, and a fresh ad-hoc runner timed out enabling UI automation. These infrastructure failures are retained in `MacUISettings.xcresult`, `MacUISignedSettings.xcresult` and `MacUIFreshSignedSettings.xcresult`; they are not passing test evidence. Native macOS interaction was checked separately through computer-use automation without changing host security settings. That check caught sidebar truncation, selectable text missing from accessibility labels, and a truncated provider explanation; those were corrected before the final native check.

The final native Mac screenshots are `mac-settings-firebase.png`, `mac-console.png` and `mac-developer-disabled.png` under `output/developer-settings-v2/`, with corresponding accessibility snapshots. The disabled Window menu and empty Developer menu were read back separately; neither exposed a foundation or console action. Command–Option–D and Command–Option–L remained inactive after access was revoked. See `mac-native-validation.md` for the exact checks and runner limitation.

No other app repository was migrated. No provider provisioning, production delivery, physical-device validation, distribution archive or TestFlight release was performed. The UI and client configuration do not prove Google Analytics linking, Firebase/Sentry backend receipt, Sentry archive-symbol availability or real RevenueCat purchase/restore behavior. visionOS runtime interaction remains unverified; its device compile check is recorded separately.

## 0.5.0 release preparation

`VERSION`, the generated `FoundationVersion.current`, sample marketing versions, setup defaults and release documentation use **0.5.0**. Independent adapters and developer settings are first published in 0.5.0. Explicitly pinned 0.3.1 integrations retain their compatible generation path. The new remote-default regression check verifies that both XcodeGen and native Xcode setup pin 0.5.0 and register its shared developer-link contract.

After the version update, all **50 core tests** passed (`output/release-0.5.0/core-tests.log`) and all **53 Python tooling tests** passed (`tooling-tests.log`: 15 setup, 5 metadata, 24 report inspector and 9 transcription tests). The generated Swift version is checked against `VERSION` and `Package.resolved` by the metadata suite. Existing adapter, reporting, platform build and SDK-isolation checks above retain their original evidence.

The version-updated iOS sample and UI target built successfully (`ios-version-build.log`). A focused settings scenario passed with the **0.5.0** display assertion, missing optional providers, developer disable/persistence and re-enable (`VersionUI.xcresult`, `ios-version-ui.log`). The built app's `CFBundleShortVersionString` and `MZFoundationBuildMetadata.plist` were also read back as 0.5.0. The staged release changes passed Gitleaks with no findings (`gitleaks.log`, `gitleaks.json`).
