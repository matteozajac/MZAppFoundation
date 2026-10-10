import FirebaseCore
import MZAppFoundation
@testable import MZAppFoundationFirebaseAnalytics
@testable import MZAppFoundationSentry
import Sentry
import XCTest

@MainActor final class HostAdapterTests: XCTestCase {
    func testReusedFirebaseDoesNotInitializeAndConsentRemainsIndependent() throws {
        let client = FakeFirebaseAnalyticsClient(application: Self.application())
        let engine = try FirebaseAnalyticsEngine(options: Self.options(), initialization: .reuseExistingDefaultApp,
                                               client: client, remoteAllowed: { true })
        XCTAssertTrue(engine.managesAnalytics)
        XCTAssertFalse(engine.ownsRunningSDK)
        XCTAssertEqual(client.configureCount, 0)
        XCTAssertTrue(client.consents.isEmpty)
        XCTAssertTrue(client.events.isEmpty)
        XCTAssertEqual(engine.record(.init("fixture")), .ignored)
        engine.setEnabled(true)
        XCTAssertEqual(engine.record(.init("fixture")), .recorded)
        engine.setEnabled(false)
        XCTAssertEqual(engine.record(.init("fixture")), .ignored)
        XCTAssertEqual(client.consents, [true, false])
        XCTAssertEqual(client.configureCount, 0)
        XCTAssertEqual(client.events.count, 1)
    }

    func testReuseRejectsMissingAndMismatchedFirebaseWithoutSideEffects() {
        for app in [nil, Self.application(project: "other"), Self.application(app: "other"),
                    Self.application(bundle: "com.example.other")] {
            let client = FakeFirebaseAnalyticsClient(application: app)
            XCTAssertThrowsError(try FirebaseAnalyticsEngine(options: Self.options(), initialization: .reuseExistingDefaultApp,
                                                            client: client, remoteAllowed: { true }))
            XCTAssertEqual(client.configureCount, 0)
            XCTAssertTrue(client.consents.isEmpty)
        }
    }

    func testFoundationInitializationIsLazyAndDoesNotAdoptACompetingApp() throws {
        let client = FakeFirebaseAnalyticsClient()
        let engine = try FirebaseAnalyticsEngine(options: Self.options(), initialization: .initializeDefaultApp,
                                               client: client, remoteAllowed: { true })
        engine.setEnabled(false)
        XCTAssertEqual(client.configureCount, 0)
        client.application = Self.application()
        engine.setEnabled(true)
        XCTAssertFalse(engine.managesAnalytics)
        XCTAssertTrue(client.consents.isEmpty)
        XCTAssertEqual(client.configureCount, 0)
    }

    func testFoundationInitializesOnceAndReplacementRevokesAnalytics() throws {
        let client = FakeFirebaseAnalyticsClient()
        let engine = try FirebaseAnalyticsEngine(options: Self.options(), initialization: .initializeDefaultApp,
                                               client: client, remoteAllowed: { true })
        engine.setEnabled(true)
        engine.setEnabled(true)
        XCTAssertEqual(client.configureCount, 1)
        XCTAssertTrue(engine.managesAnalytics)
        client.application = Self.application()
        XCTAssertFalse(engine.managesAnalytics)
        XCTAssertEqual(engine.record(.init("fixture")), .ignored)
        engine.setEnabled(false)
        XCTAssertEqual(client.consents, [true, true])
        engine.setEnabled(true)
        XCTAssertEqual(client.configureCount, 1)
    }

    func testReuseCannotRebindAfterReplacementAndRuntimeRevocationBlocksDelivery() throws {
        let client = FakeFirebaseAnalyticsClient(application: Self.application())
        let gate = FakeRuntimeGate()
        let engine = try FirebaseAnalyticsEngine(options: Self.options(), initialization: .reuseExistingDefaultApp,
                                               client: client, remoteAllowed: { gate.allowed })
        engine.setEnabled(true)
        gate.allowed = false
        XCTAssertEqual(engine.record(.init("fixture")), .ignored)
        engine.setEnabled(true)
        XCTAssertEqual(client.consents, [true, false])
        client.application = Self.application()
        gate.allowed = true
        engine.setEnabled(true)
        XCTAssertFalse(engine.managesAnalytics)
        XCTAssertEqual(client.consents, [true, false])
    }

    func testRuntimeSuppressionRejectsBothModesWithoutSDKCalls() {
        for mode in [FirebaseAnalyticsInitialization.initializeDefaultApp, .reuseExistingDefaultApp] {
            let client = FakeFirebaseAnalyticsClient(application: Self.application())
            XCTAssertThrowsError(try FirebaseAnalyticsEngine(options: Self.options(), initialization: mode,
                                                            client: client, remoteAllowed: { false }))
            XCTAssertEqual(client.configureCount, 0)
            XCTAssertTrue(client.consents.isEmpty)
            XCTAssertTrue(client.events.isEmpty)
        }
    }

    func testSentryFilterSeesBaselineSanitizationAndCannotRestorePII() throws {
        let event = Event(level: .error)
        event.extra = ["secret": "fixture"]
        event.user = User(userId: "fixture")
        let filtered = try XCTUnwrap(SentryDiagnostics.filteredEvent(event) { value in
            XCTAssertNil(value.extra)
            XCTAssertNil(value.user)
            value.extra = ["restored": "fixture"]
            value.user = User(userId: "restored")
            value.message = SentryMessage(formatted: "safe.operation")
            return value
        })
        XCTAssertNil(filtered.extra)
        XCTAssertNil(filtered.user)
        XCTAssertEqual(filtered.message?.formatted, "safe.operation")
        XCTAssertNil(SentryDiagnostics.filteredEvent(event, filter: { _ in nil }))
        XCTAssertNotNil(SentryDiagnostics.filteredEvent(event, filter: nil))
    }

    private static func options() -> FirebaseOptions {
        let options = FirebaseOptions(googleAppID: "1:123:ios:fixture", gcmSenderID: "123")
        options.projectID = "fixture"; options.bundleID = "com.example.fixture"
        return options
    }
    private static func application(project: String = "fixture", app: String = "1:123:ios:fixture",
                                    bundle: String = "com.example.fixture") -> FirebaseAnalyticsApplication {
        .init(instance: NSObject(), projectID: project, appID: app, bundleID: bundle)
    }
}

@MainActor private final class FakeRuntimeGate { var allowed = true }

@MainActor private final class FakeFirebaseAnalyticsClient: FirebaseAnalyticsClient {
    var application: FirebaseAnalyticsApplication?
    var configureCount = 0
    var consents: [Bool] = []
    var events: [TelemetryEvent] = []
    init(application: FirebaseAnalyticsApplication? = nil) { self.application = application }
    func configure(options: FirebaseOptions) {
        configureCount += 1
        application = .init(instance: NSObject(), projectID: options.projectID,
                            appID: options.googleAppID, bundleID: options.bundleID)
    }
    func setConsent(enabled: Bool) { consents.append(enabled) }
    func record(_ event: TelemetryEvent) { events.append(event) }
}
