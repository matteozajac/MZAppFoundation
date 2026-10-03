import Foundation

@MainActor public final class AppServices {
    public let configuration: AppConfiguration
    public let analytics: any AnalyticsTracking
    public let diagnostics: any DiagnosticsReporting
    public let logger: any AppLogging
    public let loggingProvider: String
    public let purchases: any PurchaseProviding
    public let developerOptions: DeveloperOptions
    public let telemetry: Telemetry
    public let foundationDiagnostics: FoundationDiagnostics

    public init(configuration: AppConfiguration, telemetry: Telemetry, logger: any AppLogging,
                purchases: any PurchaseProviding, developerOptions: DeveloperOptions,
                foundationDiagnostics: FoundationDiagnostics = .init()) {
        self.configuration = configuration; self.telemetry = telemetry
        self.loggingProvider = String(describing: type(of: logger))
        self.analytics = telemetry; self.diagnostics = telemetry; self.logger = DiagnosticsLogger(local: logger, diagnostics: telemetry)
        self.purchases = purchases; self.developerOptions = developerOptions
        self.foundationDiagnostics = foundationDiagnostics
        telemetry.timeline.record(.startup, category: .startup, status: .recorded)
        for record in foundationDiagnostics.startupRecords {
            telemetry.timeline.record(.providerStartup, category: .startup,
                status: record.status == .failed ? .failed : (record.status == .skipped ? .ignored : .recorded), provider: record.provider)
        }
        developerOptions.onActivity = { [weak telemetry] code in
            telemetry?.timeline.record(code == "developer.access.expired" ? .developerAccessExpired :
                (code == "developer.link.rejected" ? .developerLinkRejected : .developerAccessChanged),
                                       category: .developerOptions, status: .updated)
        }
    }
    public var providerSnapshots: [ProviderSnapshot] {
        foundationDiagnostics.snapshots(configuration: configuration, preferences: telemetry.preferences)
    }
    public var additionalDiagnosticSections: [FoundationDiagnosticSection] {
        foundationDiagnostics.sections(configuration: configuration, preferences: telemetry.preferences)
    }
    public var providerInspectionContext: ProviderInspectionContext {
        .init(configuration: configuration, preferences: telemetry.preferences,
              remoteAllowed: RuntimeSafety.permitsRemote(environment: configuration.environment))
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
