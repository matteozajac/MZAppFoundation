# Developer tools 0.5.1 validation — 3 October 2026

Automated evidence is stored in `output/developer-tools-0.5.1/` (ignored). Earlier large validation caches were preserved under `.build/archived-validation-output/`; `output/validation-artifact-locations.json` records their previous/current locations. This keeps generated SDK trees out of Xcode's recursive package file enumeration.

- SDK-free Core/UI: 52 tests passed, including two shortcut catalog/formatting tests and strict canonical deep-link parsing.
- Python setup, build metadata and report tooling: 55 tests passed. Default remote/native generation pins 0.5.1, emits short app-scheme URLs and removes only the obsolete shared registration.
- Hosted iPad native tests: 4 passed in `native-release.xcresult`. Real UIApplication responder action resolution covers Command–D with no focused input and with a focused text field in a sheet. Forwarded UIKit shake above an alert, sheet/alert identity, typed text, disabled access, originating scene, restored key window, duplicate report dismissal, pending-export file retention and safe reopening are checked.
- Reporting: 34 tests passed in `reporting.xcresult`, covering retention, media encoding, capture lifecycle, Pulse export, voice limits and real ZIP round trips.
- iPad UI: 3 existing reporting/settings tests passed in `ui.xcresult`; help remains available with developer mode off in `help.xcresult`. Screenshots and UI attachments were retained. Root navigation/safe-area layout was visually inspected in `ipad-root.png`.
- Native macOS sample and UI-test target compiled. Both attempts to run macOS XCTest stalled before the runner established its connection; `mac-signed.xcresult` records the infrastructure error. This is not a passing macOS runtime test.
- visionOS sample compiled with Command–D and shared help; standalone Core/UI builds also passed on macOS, iOS and visionOS.

The idle-screen regression failed before the root controller supplied a fallback responder. The final four-test hosted run passes after that fix; existing text responders are preserved. No permanent key window, global UIWindow override or method swizzling is used.

Physical Magic Keyboard key delivery, accelerometer shake, ReplayKit consent/performance, microphone capture and interruption behavior remain device acceptance checks. The UI sample disables rolling capture during automated tests. macOS shortcut execution and visionOS keyboard execution are not established by compilation. Bedtime Stories adoption and Internal TestFlight delivery have their own app validation record.
