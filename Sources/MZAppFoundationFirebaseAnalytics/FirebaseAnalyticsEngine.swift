import Foundation
import MZAppFoundation
#if os(iOS)
import FirebaseCore
import FirebaseAnalytics

/// Reuse must be deliberate: another default Firebase app is never silently adopted.
public enum FirebaseAnalyticsInitialization: Equatable, Sendable {
    case initializeDefaultApp
    case reuseExistingDefaultApp
}

@MainActor struct FirebaseAnalyticsApplication {
    let instance: AnyObject
    let projectID: String?
    let appID: String
    let bundleID: String?
}

/// Internal injection isolates ownership/consent tests from the live SDK.
@MainActor protocol FirebaseAnalyticsClient: AnyObject {
    var application: FirebaseAnalyticsApplication? { get }
    func configure(options: FirebaseOptions)
    func setConsent(enabled: Bool)
    func record(_ event: TelemetryEvent)
}

@MainActor private final class LiveFirebaseAnalyticsClient: FirebaseAnalyticsClient {
    var application: FirebaseAnalyticsApplication? {
        guard let app = FirebaseApp.allApps?["__FIRAPP_DEFAULT"] else { return nil }
        return .init(instance: app, projectID: app.options.projectID,
                     appID: app.options.googleAppID, bundleID: app.options.bundleID)
    }
    func configure(options: FirebaseOptions) { FirebaseApp.configure(options: options) }
    func setConsent(enabled: Bool) {
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
        FirebaseAnalytics.Analytics.setConsent([
            .analyticsStorage: enabled ? .granted : .denied,
            .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied
        ])
        if !enabled { FirebaseAnalytics.Analytics.resetAnalyticsData() }
    }
    func record(_ event: TelemetryEvent) {
        let properties: [String: Any] = event.properties.mapValues { value in
            switch value {
            case .string(let value): value
            case .integer(let value): value
            case .double(let value): value
            case .bool(let value): value
            }
        }
        FirebaseAnalytics.Analytics.logEvent(event.name, parameters: properties)
    }
}

@MainActor public final class FirebaseAnalyticsEngine: AnalyticsEngine {
    public let delivery = DeliveryKind.remote
    private static weak var owner: FirebaseAnalyticsEngine?
    private weak var boundApp: AnyObject?
    private let options: FirebaseOptions
    private let initialization: FirebaseAnalyticsInitialization
    private let client: any FirebaseAnalyticsClient
    private let remoteAllowed: @MainActor () -> Bool
    private var initializedDefaultApp = false
    private var enabled = false

    public static var ownership: ProviderOwnership {
        guard let app = FirebaseApp.allApps?["__FIRAPP_DEFAULT"] else { return .notInitialized }
        return owner?.initializedDefaultApp == true && owner?.boundApp === app ? .ownedByComposition : .external
    }
    public static var runningIdentity: ProviderProjectIdentity? {
        guard let options = FirebaseApp.allApps?["__FIRAPP_DEFAULT"]?.options else { return nil }
        return .init(projectID: options.projectID, appID: options.googleAppID)
    }
    public var ownsRunningSDK: Bool { Self.owner === self && initializedDefaultApp && managesAnalytics }
    /// Analytics control and Firebase startup ownership are separate responsibilities.
    public var managesAnalytics: Bool {
        guard let boundApp, let current = client.application else { return false }
        return boundApp === current.instance && Self.matches(current, options: options)
    }

    public convenience init(configuration: AppConfiguration, path: String,
                            initialization: FirebaseAnalyticsInitialization = .initializeDefaultApp) throws {
        let file = FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: path)
        guard file.state == .configured, let options = FirebaseOptions(contentsOfFile: path) else {
            throw BootstrapFailure.invalidFirebaseConfiguration
        }
        try self.init(options: options, initialization: initialization, client: LiveFirebaseAnalyticsClient(),
                      remoteAllowed: { RuntimeSafety.permitsRemote(environment: configuration.environment) })
    }

    init(options: FirebaseOptions, initialization: FirebaseAnalyticsInitialization,
         client: any FirebaseAnalyticsClient, remoteAllowed: @escaping @MainActor () -> Bool) throws {
        guard remoteAllowed() else { throw BootstrapFailure.configurationConflict }
        self.options = options; self.initialization = initialization
        self.client = client; self.remoteAllowed = remoteAllowed
        switch initialization {
        case .initializeDefaultApp:
            guard client.application == nil else { throw BootstrapFailure.configurationConflict }
        case .reuseExistingDefaultApp:
            guard let app = client.application, Self.matches(app, options: options) else {
                throw BootstrapFailure.configurationConflict
            }
            boundApp = app.instance
        }
    }

    private static func matches(_ app: FirebaseAnalyticsApplication, options: FirebaseOptions) -> Bool {
        app.bundleID == options.bundleID && app.appID == options.googleAppID
            && app.projectID == options.projectID && app.projectID?.isEmpty == false
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled && remoteAllowed()
        if self.enabled, boundApp == nil, initialization == .initializeDefaultApp {
            // A competing initializer or replacement must never be taken over.
            guard !initializedDefaultApp, client.application == nil else { self.enabled = false; return }
            client.configure(options: options)
            guard let app = client.application, Self.matches(app, options: options) else {
                self.enabled = false; return
            }
            boundApp = app.instance; initializedDefaultApp = true; Self.owner = self
        }
        guard managesAnalytics else { self.enabled = false; return }
        client.setConsent(enabled: self.enabled)
    }

    public func record(_ event: TelemetryEvent) -> EngineResult {
        guard enabled, remoteAllowed(), managesAnalytics else { return .ignored }
        client.record(event)
        return .recorded
    }

    public func submitVerification(context: ProviderInspectionContext) -> ProviderVerificationResult {
        guard context.remoteAllowed, context.preferences.analytics, enabled, remoteAllowed(), managesAnalytics else {
            return .init(status: .unavailable, code: "firebase.verification_blocked",
                message: "Enable analytics delivery in a permitted runtime before submitting the verification event.")
        }
        let reference = UUID().uuidString
        client.record(TelemetryEvent("mz_developer_verification", properties: ["verification_id": .string(reference)]))
        return .init(status: .submitted, code: "firebase.verification_submitted",
            message: "A tagged event was submitted to the Firebase Analytics SDK. Confirm it in DebugView with the SDK's debug mode enabled. This does not prove backend receipt. Reference: \(reference).",
            reference: reference)
    }
}
#endif
