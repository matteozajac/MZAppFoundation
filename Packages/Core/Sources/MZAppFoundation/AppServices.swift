import Foundation

@MainActor public final class AppServices {
    public let configuration: AppConfiguration
    public let analytics: any AnalyticsTracking
    public let diagnostics: any DiagnosticsReporting
    public let logger: any AppLogging
    public let purchases: any PurchaseProviding
    public let developerOptions: DeveloperOptions
    public let telemetry: Telemetry

    public init(configuration: AppConfiguration, telemetry: Telemetry, logger: any AppLogging,
                purchases: any PurchaseProviding, developerOptions: DeveloperOptions) {
        self.configuration = configuration; self.telemetry = telemetry
        self.analytics = telemetry; self.diagnostics = telemetry; self.logger = DiagnosticsLogger(local: logger, diagnostics: telemetry)
        self.purchases = purchases; self.developerOptions = developerOptions
    }
    public static func testing(configuration: AppConfiguration, schema: TelemetrySchema,
                               analytics: RecordingAnalyticsEngine = .init(),
                               diagnostics: RecordingDiagnosticsEngine = .init(),
                               purchases: any PurchaseProviding = MockPurchases(), defaults: UserDefaults) -> AppServices {
        AppServices(configuration: configuration,
                    telemetry: Telemetry(configuration: configuration, schema: schema,
                                         analytics: [analytics], diagnostics: [diagnostics]),
                    logger: RecordingLogger(), purchases: purchases,
                    developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults))
    }
}
