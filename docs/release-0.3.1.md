# MZAppFoundation 0.3.1

Firebase is pinned to 12.19.2, matching the current BedtimeStories backend dependency. Pulse 5.2.1, Sentry 9.27.0 and RevenueCat 5.88.0 retain their verified pins. No provider resource or delivery preference changes are part of this release.

Native setup now preserves Xcode's synchronized source groups on the local target. Generated bootstrap failures retain the actual error and caller evidence.

Validation on 2026-10-02, Xcode 27.0 (27A266a): 22 standalone core tests, 11 setup tests including repeated synchronized-group setup, and the iOS Internal device composition build passed without signing. BedtimeStories also passed 39 simulator tests, including UIKit shake-callback presentation, developer-mode disable/persistence, underlying-error identity, caller forwarding, private-text exclusion and cancellation handling. Physical-device motion and provider delivery are separate checks.
