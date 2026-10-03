import Foundation
import MZAppFoundation
#if os(iOS)
import FirebaseCore
import FirebaseAnalytics

@MainActor public final class FirebaseAnalyticsEngine: AnalyticsEngine {
    public let delivery = DeliveryKind.remote
    private static weak var owner: FirebaseAnalyticsEngine?
    private weak var ownedApp: FirebaseApp?
    private let configuration: AppConfiguration
    private let options: FirebaseOptions
    private var enabled = false
    // The public default-app name is documented by FirebaseCore. Reading this inventory
    // never configures Firebase; the SDK may log its own absence diagnostic.
    private static var defaultApp: FirebaseApp? { FirebaseApp.allApps?["__FIRAPP_DEFAULT"] }

    public static var ownership: ProviderOwnership {
        guard let app = defaultApp else { return .notInitialized }
        return owner?.ownedApp === app ? .ownedByComposition : .external
    }
    public static var runningIdentity: ProviderProjectIdentity? {
        guard let options = defaultApp?.options else { return nil }
        return .init(projectID: options.projectID, appID: options.googleAppID)
    }
    public var ownsRunningSDK: Bool { Self.owner === self && ownedApp != nil && ownedApp === Self.defaultApp }

    public init(configuration: AppConfiguration, path: String) throws {
        let file = FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: path)
        guard file.state == .configured, let options = FirebaseOptions(contentsOfFile: path) else {
            throw BootstrapFailure.invalidFirebaseConfiguration
        }
        guard RuntimeSafety.permitsRemote(environment: configuration.environment), Self.defaultApp == nil else {
            throw BootstrapFailure.configurationConflict
        }
        self.configuration = configuration; self.options = options
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled && RuntimeSafety.permitsRemote(environment: configuration.environment)
        if self.enabled, Self.defaultApp == nil {
            FirebaseApp.configure(options: options)
            ownedApp = Self.defaultApp; Self.owner = self
        }
        guard let ownedApp, ownedApp === Self.defaultApp else { self.enabled = false; return }
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(self.enabled)
        FirebaseAnalytics.Analytics.setConsent([
            .analyticsStorage: self.enabled ? .granted : .denied,
            .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied
        ])
        if !self.enabled { FirebaseAnalytics.Analytics.resetAnalyticsData() }
    }

    public func record(_ event: TelemetryEvent) -> EngineResult {
        guard enabled, ownsRunningSDK else { return .ignored }
        let properties: [String: Any] = event.properties.mapValues { value in
            switch value {
            case .string(let value): value
            case .integer(let value): value
            case .double(let value): value
            case .bool(let value): value
            }
        }
        FirebaseAnalytics.Analytics.logEvent(event.name, parameters: properties)
        return .recorded
    }

    public func submitVerification(context: ProviderInspectionContext) -> ProviderVerificationResult {
        guard context.remoteAllowed, context.preferences.analytics, enabled, ownsRunningSDK else {
            return .init(status: .unavailable, code: "firebase.verification_blocked",
                message: "Enable analytics delivery in a permitted runtime before submitting the verification event.")
        }
        let reference = UUID().uuidString
        FirebaseAnalytics.Analytics.logEvent("mz_developer_verification", parameters: ["verification_id": reference])
        return .init(status: .submitted, code: "firebase.verification_submitted",
            message: "A tagged event was submitted to the Firebase Analytics SDK. Confirm it in DebugView with the SDK's debug mode enabled. This does not prove backend receipt. Reference: \(reference).",
            reference: reference)
    }
}
#endif
