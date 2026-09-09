import Foundation
import MZAppFoundation
import MZAppFoundationLive
import MZAppFoundationLocal
#if os(iOS)
import FirebaseCore
import FirebaseAnalytics

@MainActor private final class FirebaseAnalyticsEngine: AnalyticsEngine {
    let delivery = DeliveryKind.remote
    private let configuration: AppConfiguration
    private let options: FirebaseOptions
    private var enabled = false
    init(configuration: AppConfiguration, path: String) throws {
        guard let options = FirebaseOptions(contentsOfFile: path), options.bundleID == configuration.bundleIdentifier,
              options.projectID?.isEmpty == false else { throw BootstrapFailure.invalidFirebaseConfiguration }
        if let existing = FirebaseApp.app(), existing.options.googleAppID != options.googleAppID {
            throw BootstrapFailure.configurationConflict
        }
        self.configuration = configuration; self.options = options
    }
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled && RuntimeSafety.permitsRemote(environment: configuration.environment)
        if self.enabled && FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        if FirebaseApp.app() != nil {
            FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(self.enabled)
            FirebaseAnalytics.Analytics.setConsent([
                .analyticsStorage: self.enabled ? .granted : .denied,
                .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied
            ])
            if !self.enabled { FirebaseAnalytics.Analytics.resetAnalyticsData() }
        }
    }
    func record(_ event: TelemetryEvent) -> EngineResult {
        guard enabled else { return .ignored }
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
}
#endif

@MainActor public enum FirebaseServices {
    private static var cached: AppServices?
    private static var cachedPath: String?
    private static var cachedVendors: LiveConfiguration?
    private static var cachedSchema: TelemetrySchema?
    public static func make(configuration: AppConfiguration, vendors: LiveConfiguration, schema: TelemetrySchema,
                            googleServiceInfoPath: String?, defaults: UserDefaults = .standard) throws -> AppServices {
        guard RuntimeSafety.permitsRemote(environment: configuration.environment) else {
            return LocalServices.make(configuration: configuration, schema: schema, defaults: defaults)
        }
        if let cached {
            guard cached.configuration == configuration, cachedVendors == vendors,
                  cachedPath == googleServiceInfoPath, cachedSchema == schema else { throw BootstrapFailure.configurationConflict }
            return cached
        }
        var analytics: [any AnalyticsEngine] = []
        #if os(iOS)
        if let path = googleServiceInfoPath {
            analytics.append(try FirebaseAnalyticsEngine(configuration: configuration, path: path))
        }
        #endif
        let services = try LiveServices.make(configuration: configuration, vendors: vendors, schema: schema,
                                     additionalAnalytics: analytics, defaults: defaults)
        cached = services; cachedPath = googleServiceInfoPath; cachedVendors = vendors; cachedSchema = schema
        return services
    }
}
