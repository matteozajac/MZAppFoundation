import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct FoundationTests {
    private let schema = TelemetrySchema(events: ["sample_action": ["count", "duration", "token", "note"]])
    private func configuration(_ environment: AppEnvironment = .local) -> AppConfiguration {
        AppConfiguration(bundleIdentifier: "com.example.tests", urlScheme: "mzsample", environment: environment)
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "mz.tests." + UUID().uuidString)! }

    @Test func typedValuesAndSchemaFiltering() {
        let recorder = RecordingAnalyticsEngine()
        let telemetry = Telemetry(configuration: configuration(), schema: schema, analytics: [recorder])
        telemetry.track(TelemetryEvent("sample_action", properties: ["count": .integer(3), "duration": .double(1.25),
                                                                   "token": .string("private"), "unknown": .bool(true)]))
        telemetry.track(TelemetryEvent("unregistered"))
        #expect(recorder.events == [TelemetryEvent("sample_action", properties: ["count": .integer(3), "duration": .double(1.25)])])
    }
    @Test func rejectsNonFiniteAndOversizedProperties() {
        let event = schema.validate(TelemetryEvent("sample_action", properties: ["duration": .double(.infinity), "note": .string(String(repeating: "x", count: 101))]))
        #expect(event?.properties.isEmpty == true)
    }
    @Test func providerFailureDoesNotStopFanout() {
        let failing = RecordingAnalyticsEngine(); failing.result = .failed
        let healthy = RecordingAnalyticsEngine()
        let telemetry = Telemetry(configuration: configuration(), schema: schema, analytics: [failing, healthy])
        telemetry.track(TelemetryEvent("sample_action"))
        #expect(healthy.events.count == 1)
    }
    @Test func localEnvironmentCannotEnableRemoteEngines() {
        let remote = RecordingAnalyticsEngine(delivery: .remote)
        let local = RecordingAnalyticsEngine()
        let telemetry = Telemetry(configuration: configuration(), schema: schema, analytics: [remote, local])
        telemetry.updatePreferences(.init(analytics: true, diagnostics: true))
        telemetry.track(TelemetryEvent("sample_action"))
        #expect(!remote.enabled && remote.events.isEmpty)
        #expect(local.events.count == 1)
    }
    @Test func independentPreferencesPreserveLocalDiagnostics() {
        let local = RecordingDiagnosticsEngine()
        let remote = RecordingDiagnosticsEngine(delivery: .remote)
        let telemetry = Telemetry(configuration: configuration(), schema: schema, diagnostics: [local, remote])
        telemetry.updatePreferences(.init(analytics: false, diagnostics: false))
        telemetry.record(DiagnosticIssue(code: "offline", category: "network", metadata: ["Authorization": .string("private"), "attempt": .integer(2)]))
        #expect(local.issues.first?.metadata == ["attempt": .integer(2)])
        #expect(remote.issues.isEmpty)
    }
    @Test func developerDefaultsAndPersistence() {
        let store = defaults()
        let options = DeveloperOptions(configuration: configuration(.production), defaults: store)
        #expect(!options.isEnabled)
        #expect(options.handle(URL(string: "mzsample://developer/enable")!))
        #expect(options.allowsNetworkCapture)
        #expect(DeveloperOptions(configuration: configuration(.production), defaults: store).isEnabled)
        options.requestConsole(); #expect(options.consoleRequested)
        #expect(options.handle(URL(string: "mzsample://developer/disable")!))
        #expect(!options.consoleRequested && !options.allowsNetworkCapture)
    }
    @Test(arguments: ["other://developer/enable", "mzsample://developer/enable?x=1", "mzsample://developer/enable#x",
                      "mzsample://user@developer/enable", "mzsample://developer:80/enable", "mzsample://developer/enable/",
                      "mzsample://developer/%65nable", "mzsample://developer/unknown"])
    func rejectsMalformedDeveloperLinks(link: String) {
        let options = DeveloperOptions(configuration: configuration(.production), defaults: defaults())
        #expect(!options.handle(URL(string: link)!))
        #expect(!options.isEnabled)
    }
    @Test func spatialLaunchOnlyOnceAndExplicitDisableWins() {
        let store = defaults()
        let options = DeveloperOptions(configuration: configuration(), defaults: store)
        options.launchSpatialConsole(); #expect(options.consoleRequested)
        options.dismissConsole(); options.launchSpatialConsole(); #expect(!options.consoleRequested)
        options.setEnabled(false)
        let relaunched = DeveloperOptions(configuration: configuration(), defaults: store)
        relaunched.launchSpatialConsole(); #expect(!relaunched.consoleRequested)
    }
    @Test func mockPurchaseOutcomesAndRestore() async throws {
        let offer = PurchaseOffer(id: "lifetime", offeringID: "main", productID: "premium", title: "Premium", localizedPrice: "$9.99")
        let mock = MockPurchases(offers: [offer])
        #expect(try await mock.purchase(offer) == .cancelled)
        mock.purchaseResult = .success(.pending)
        #expect(try await mock.purchase(offer) == .pending)
        #expect(mock.cachedState?.active.isEmpty == true)
        let premium = EntitlementState(active: ["premium"])
        mock.purchaseResult = .success(.purchased(premium))
        #expect(try await mock.purchase(offer) == .purchased(premium))
        mock.restoreResult = .success(premium)
        #expect(try await mock.restore() == premium)
        _ = try await mock.identify("another-user")
        #expect(mock.cachedState?.active.isEmpty == true)
    }
    @Test func streamIncludesRevocationAndFinishes() async {
        let mock = MockPurchases()
        var iterator = mock.updates().makeAsyncIterator()
        #expect(await iterator.next() == .init())
        mock.send(.init(active: ["premium"]))
        #expect(await iterator.next()?.hasAccess(to: "premium") == true)
        mock.send(.init()); #expect(await iterator.next()?.active.isEmpty == true)
        mock.finish(); #expect(await iterator.next() == nil)
    }
    @Test func failedVerificationNeverGrantsAccess() {
        #expect(!EntitlementState(active: ["premium"], verificationFailed: true).hasAccess(to: "premium"))
    }
    @Test func missingConfigurationDoesNotGrantAccess() async {
        let purchases = UnavailablePurchases()
        #expect(purchases.cachedState == nil)
        await #expect(throws: PurchaseFailure.unavailable) { try await purchases.restore() }
    }
    @Test func mocksAreIsolatedBetweenCompositions() {
        let first = MockPurchases(); first.send(.init(active: ["premium"]))
        #expect(MockPurchases().cachedState?.active.isEmpty == true)
        #expect(UnavailablePurchases().cachedState == nil)
    }
    @Test func delayedRefreshCannotOverwriteNewerEntitlements() {
        let ledger = EntitlementLedger()
        let older = ledger.beginRequest()
        let newer = ledger.beginRequest()
        #expect(ledger.apply(.init(active: ["premium"]), ticket: newer))
        #expect(!ledger.apply(.init(), ticket: older))
        #expect(ledger.state?.hasAccess(to: "premium") == true)
    }
    @Test func revocationInvalidatesOutstandingResponses() {
        let ledger = EntitlementLedger(state: .init(active: ["premium"]))
        let pending = ledger.beginRequest()
        ledger.receive(.init())
        #expect(!ledger.apply(.init(active: ["premium"]), ticket: pending))
        #expect(ledger.state?.active.isEmpty == true)
    }
    @Test func additionalRedactionKeysAreCaseInsensitive() {
        let logger = RecordingLogger(redaction: .init(additionalSensitiveKeys: ["CUSTOM"]))
        logger.log(LogEntry("technical_event", metadata: ["custom": .string("private"), "attempt": .integer(1)]))
        #expect(logger.entries.first?.metadata == ["attempt": .integer(1)])
    }
}
