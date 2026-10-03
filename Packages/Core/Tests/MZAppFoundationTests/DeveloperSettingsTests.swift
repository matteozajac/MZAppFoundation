import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct DeveloperSettingsTests {
    private func configuration(_ environment: AppEnvironment = .production, bundle: String = "com.example.first") -> AppConfiguration {
        .init(bundleIdentifier: bundle, urlScheme: "legacy", environment: environment, developerLinkHost: "first")
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "mz.settings.tests." + UUID().uuidString)! }

    @Test func sharedKeyMigratesExplicitFalseAndCanonicalValueWins() {
        let store = defaults()
        store.set(false, forKey: "com.example.first.developer.enabled")
        let options = DeveloperOptions(configuration: configuration(.local), defaults: store)
        #expect(!options.isEnabled)
        #expect(options.activationSource == .migrated)
        #expect(store.object(forKey: DeveloperOptions.preferenceKey) as? Bool == false)
        options.setEnabled(true)
        #expect(options.activationSource == .manual)
        #expect(DeveloperOptions(configuration: configuration(), defaults: store).isEnabled)
        // Bundle ID no longer changes the key within the same supplied store.
        #expect(DeveloperOptions(configuration: configuration(bundle: "com.example.second"), defaults: store).isEnabled)
    }

    @Test func appCanMigrateItsOwnOlderKeyWithoutChangingPublicDefaults() {
        let store = defaults()
        store.set(true, forKey: "older.app.developer")
        let options = DeveloperOptions(configuration: configuration(), defaults: store, legacyPreferenceKeys: ["older.app.developer"])
        #expect(options.isEnabled)
        #expect(!DeveloperOptions(configuration: configuration(), defaults: defaults()).isEnabled)
    }

    @Test func canonicalLinksRoundTripAndDisableRevokesCaptureAndConsole() throws {
        let options = DeveloperOptions(configuration: configuration(), defaults: defaults())
        let enable = try #require(DeveloperDeepLink.url(for: .enable, scheme: "legacy"))
        #expect(enable.absoluteString == "legacy://developer/enable")
        #expect(options.handle(enable))
        #expect(options.activationSource == .link)
        #expect(options.handle(try #require(DeveloperDeepLink.url(for: .enable, host: "first", scheme: "legacy"))))
        options.requestConsole()
        #expect(options.isEnabled && options.consoleRequested && options.allowsNetworkCapture)
        #expect(options.handle(try #require(DeveloperDeepLink.url(for: .disable, scheme: "legacy"))))
        #expect(!options.isEnabled && !options.consoleRequested && !options.allowsNetworkCapture)
    }

    @Test(arguments: [
        "mzappfoundation://developer/enable", "mzappfoundation://first/developer/enable",
        "legacy://com.example.first/developer/enable", "legacy://first/developer/enable",
        "other://developer/enable", "legacy://developer/enable?x=1",
        "legacy://developer/enable#fragment", "legacy://user@developer/enable",
        "legacy://developer:80/enable", "legacy://developer/%65nable",
        "legacy://developer/enable/", "legacy://%64eveloper/enable",
        "legacy://developer/../enable", "legacy://developer/developer/enable",
        "legacy://developer//enable", "legacy://developer/Enable", "legacy://developer/",
        "legacy:/developer/enable"
    ])
    func malformedCanonicalLinksCannotEnableTools(link: String) throws {
        let options = DeveloperOptions(configuration: configuration(), defaults: defaults())
        #expect(!options.handle(try #require(URL(string: link))))
        #expect(!options.isEnabled)
    }

    @Test func invalidAndSharedSchemesNeverProduceDeveloperLinks() {
        for scheme in ["", "app/other", "app?key=value", "app@other", "app:80", "app_name", ".", "-app", "1app", "mzappfoundation", "MZAPPFOUNDATION"] {
            #expect(DeveloperDeepLink.url(for: .enable, scheme: scheme) == nil)
            #expect(DeveloperDeepLink.inspect("legacy://developer/enable", scheme: scheme).rejectionReason == .invalidConfiguration)
        }
    }

    @Test func appIdentityComesOnlyFromItsScheme() throws {
        let link = try #require(DeveloperDeepLink.url(for: .enable, scheme: "BEDTIMESTORIES"))
        #expect(link.absoluteString == "bedtimestories://developer/enable")
        #expect(DeveloperDeepLink.inspect("BEDTIMESTORIES://DEVELOPER/enable", scheme: "bedtimestories").accepted)
        let compatibilityLink = DeveloperDeepLink.url(for: .enable, host: "com.example.first", scheme: "bedtimestories")
        #expect(compatibilityLink == link)
        #expect(DeveloperDeepLink.url(for: .enable, host: "com.example.first") == nil)
        #expect(DeveloperDeepLink.inspect(link.absoluteString, host: "unused", legacyScheme: "bedtimestories").accepted)
        let first = DeveloperOptions(configuration: .init(bundleIdentifier: "com.example.first", urlScheme: "bedtimestories", environment: .production), defaults: defaults())
        let second = DeveloperOptions(configuration: .init(bundleIdentifier: "com.example.second", urlScheme: "otherapp", environment: .production), defaults: defaults())
        #expect(first.handle(link))
        #expect(!second.handle(link) && !second.isEnabled)
    }

    @Test func defaultsRemainIsolatedBetweenAppStores() {
        let first = defaults(), second = defaults()
        DeveloperOptions(configuration: configuration(), defaults: first).setEnabled(true)
        #expect(!DeveloperOptions(configuration: configuration(), defaults: second).isEnabled)
    }

    @Test func inspectionReportsSafeReasonsAndNeverMutatesAccess() {
        let store = defaults()
        let options = DeveloperOptions(configuration: configuration(), defaults: store)
        let canonical = DeveloperDeepLink.inspect("legacy://developer/enable", scheme: "legacy")
        #expect(canonical.accepted && canonical.action == .enable && canonical.format == .appSpecific)
        let disabled = DeveloperDeepLink.inspect("legacy://developer/disable", scheme: "legacy")
        #expect(disabled.accepted && disabled.action == .disable && disabled.format == .appSpecific)
        let rejected = DeveloperDeepLink.inspect("legacy://secret:password@developer/enable", scheme: "legacy")
        #expect(!rejected.accepted && rejected.rejectionReason == .credentials)
        #expect(!String(describing: rejected).contains("secret"))
        #expect(!options.isEnabled && store.object(forKey: DeveloperOptions.preferenceKey) == nil)
    }

    @Test(arguments: ["", "\nlegacy://developer/enable", "legacy://developer/enable\u{0000}", "legacy://developer/enable bad", String(repeating: "a", count: 4_097)])
    func inspectionRejectsMalformedRawInput(link: String) {
        #expect(DeveloperDeepLink.inspect(link, scheme: "legacy").rejectionReason == .malformedURL)
    }

    @Test func temporaryAccessReplacesPersistenceAndEndsOnNextLaunch() {
        let store = defaults()
        let options = DeveloperOptions(configuration: configuration(.local), defaults: store)
        options.setEnabled(true)
        options.enableUntilAppCloses()
        #expect(options.isEnabled && options.activationSource == .session && options.expiresAt == nil)
        #expect(store.object(forKey: DeveloperOptions.preferenceKey) as? Bool == false)
        #expect(!DeveloperOptions(configuration: configuration(.local), defaults: store).isEnabled)
        #expect(!options.enable(for: .nan) && !options.enable(for: -1))
        #expect(options.isEnabled)
    }

    @Test func timedAccessExpiresAndRevokesConsoleAndCapture() async throws {
        let options = DeveloperOptions(configuration: configuration(), defaults: defaults())
        var activities: [String] = []
        options.onActivity = { activities.append($0) }
        #expect(options.enable(for: 0.03))
        #expect(options.expiresAt != nil)
        options.requestConsole()
        // Bound the wait while verifying the real automatic expiry task.
        for _ in 0..<20 where options.isEnabled { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!options.isEnabled && !options.consoleRequested && !options.allowsNetworkCapture)
        #expect(options.expiresAt == nil)
        #expect(activities == ["developer.access.timed", "developer.access.expired"])
    }

    @Test func replacedTimerCannotDisableNewPersistentAccess() async throws {
        let options = DeveloperOptions(configuration: configuration(), defaults: defaults())
        options.enable(for: 0.03)
        options.setEnabled(true)
        try await Task.sleep(for: .milliseconds(70))
        #expect(options.isEnabled && options.expiresAt == nil && options.activationSource == .manual)
        options.enable(for: 0.02)
        options.enableUntilAppCloses()
        try await Task.sleep(for: .milliseconds(50))
        #expect(options.isEnabled && options.expiresAt == nil && options.activationSource == .session)
    }

    @Test func captureDeadlineClosesEvenBeforeMainActorCanRunExpiry() {
        let options = DeveloperOptions(configuration: configuration(), defaults: defaults())
        options.enable(for: 0.02)
        // Mimic a suspended or busy UI executor. Capture reads have their own monotonic boundary.
        Thread.sleep(forTimeInterval: 0.04)
        #expect(!options.allowsNetworkCapture)
        options.refreshExpiration()
        #expect(!options.isEnabled)
    }
}
