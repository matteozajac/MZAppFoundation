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
        let enable = try #require(DeveloperDeepLink.url(for: .enable, host: "first"))
        #expect(enable.absoluteString == "mzappfoundation://first/developer/enable")
        #expect(options.handle(enable))
        #expect(options.activationSource == .link)
        #expect(options.handle(try #require(DeveloperDeepLink.url(for: .enable, host: "first", scheme: "legacy"))))
        options.requestConsole()
        #expect(options.isEnabled && options.consoleRequested && options.allowsNetworkCapture)
        #expect(options.handle(try #require(DeveloperDeepLink.url(for: .disable, host: "first"))))
        #expect(!options.isEnabled && !options.consoleRequested && !options.allowsNetworkCapture)
    }

    @Test(arguments: [
        "mzappfoundation://second/developer/enable", "mzappfoundation://first/developer/enable?x=1",
        "mzappfoundation://first/developer/enable#fragment", "mzappfoundation://user@first/developer/enable",
        "mzappfoundation://first:80/developer/enable", "mzappfoundation://first/developer/%65nable",
        "mzappfoundation://first/developer/enable/", "mzappfoundation://%66irst/developer/enable",
        "mzappfoundation://first/developer/../enable", "mzappfoundation://first/enable",
        "legacy://%64eveloper/enable"
    ])
    func malformedCanonicalLinksCannotEnableTools(link: String) throws {
        let options = DeveloperOptions(configuration: configuration(), defaults: defaults())
        #expect(!options.handle(try #require(URL(string: link))))
        #expect(!options.isEnabled)
    }

    @Test func invalidHostsNeverProduceDeveloperLinks() {
        for host in ["", "first/other", "first?key=value", "first@other", "first:80", "first_app", ".", "-first", "first-", "first..other"] {
            #expect(DeveloperDeepLink.url(for: .enable, host: host) == nil)
        }
    }

    @Test func defaultsRemainIsolatedBetweenAppStores() {
        let first = defaults(), second = defaults()
        DeveloperOptions(configuration: configuration(), defaults: first).setEnabled(true)
        #expect(!DeveloperOptions(configuration: configuration(), defaults: second).isEnabled)
    }

    @Test func inspectionReportsSafeReasonsAndNeverMutatesAccess() {
        let store = defaults()
        let options = DeveloperOptions(configuration: configuration(), defaults: store)
        let canonical = DeveloperDeepLink.inspect("mzappfoundation://first/developer/enable", host: "first", legacyScheme: "legacy")
        #expect(canonical.accepted && canonical.action == .enable && canonical.format == .shared)
        let alias = DeveloperDeepLink.inspect("legacy://first/developer/disable", host: "first", legacyScheme: "legacy")
        #expect(alias.accepted && alias.format == .appSpecific)
        let legacy = DeveloperDeepLink.inspect("legacy://developer/enable", host: "first", legacyScheme: "legacy")
        #expect(legacy.accepted && legacy.format == .legacy)
        let rejected = DeveloperDeepLink.inspect("mzappfoundation://secret:password@first/developer/enable", host: "first")
        #expect(!rejected.accepted && rejected.rejectionReason == .credentials)
        #expect(!String(describing: rejected).contains("secret"))
        #expect(!options.isEnabled && store.object(forKey: DeveloperOptions.preferenceKey) == nil)
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
