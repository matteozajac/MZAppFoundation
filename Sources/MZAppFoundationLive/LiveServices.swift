import Foundation
import MZAppFoundation
import MZAppFoundationLocal

@MainActor public enum LiveServices {
    private static var cached: AppServices?
    private static var vendorConfiguration: LiveConfiguration?

    private static var cachedSchema: TelemetrySchema?
    private static var cachedRedaction: RedactionPolicy?
    private static var analyticsIdentity: [ObjectIdentifier] = []

    /// Call once from the app entrypoint. An identical repeated bootstrap returns the same services.
    public static func make(configuration: AppConfiguration, vendors: LiveConfiguration, schema: TelemetrySchema,
                            additionalAnalytics: [any AnalyticsEngine] = [], defaults: UserDefaults = .standard,
                            redaction: RedactionPolicy = .init()) throws -> AppServices {
        guard RuntimeSafety.permitsRemote(environment: configuration.environment) else {
            return LocalServices.make(configuration: configuration, schema: schema, defaults: defaults, redaction: redaction)
        }
        if let cached {
            guard cached.configuration == configuration, vendorConfiguration == vendors, cachedSchema == schema,
                  cachedRedaction == redaction, analyticsIdentity == additionalAnalytics.map({ ObjectIdentifier($0) }) else {
                throw BootstrapFailure.configurationConflict
            }
            return cached
        }
        let logger = PulseLogger(redaction: redaction)
        let local = LocalTelemetryEngine(logger: logger)
        var diagnostics: [any DiagnosticsEngine] = [local]
        if let dsn = vendors.sentryDSN { diagnostics.append(try SentryDiagnostics(dsn: dsn, configuration: configuration)) }
        let purchases: any PurchaseProviding
        if let key = vendors.revenueCatPublicKey { purchases = try RevenueCatPurchases(key: key) }
        else { purchases = UnavailablePurchases() }
        let services = AppServices(configuration: configuration,
                                   telemetry: Telemetry(configuration: configuration, schema: schema,
                                                        analytics: [local] + additionalAnalytics, diagnostics: diagnostics,
                                                        redaction: redaction),
                                   logger: logger, purchases: purchases,
                                   developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults))
        cached = services; vendorConfiguration = vendors
        cachedSchema = schema; cachedRedaction = redaction
        analyticsIdentity = additionalAnalytics.map { ObjectIdentifier($0) }
        return services
    }
}
