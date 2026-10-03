import Foundation
import MZAppFoundation
import MZAppFoundationLocal

@MainActor public enum LiveServices {
    private static var cached: AppServices?
    private static var vendorConfiguration: LiveConfiguration?

    private static var cachedSchema: TelemetrySchema?
    private static var cachedRedaction: RedactionPolicy?
    private static var analyticsIdentity: [ObjectIdentifier] = []
    private static var cachedDiagnosticIdentity: String?

    /// Call once from the app entrypoint. An identical repeated bootstrap returns the same services.
    public static func make(configuration: AppConfiguration, vendors: LiveConfiguration, schema: TelemetrySchema,
                            additionalAnalytics: [any AnalyticsEngine] = [], defaults: UserDefaults = .standard,
                            redaction: RedactionPolicy = .init(),
                            foundationDiagnostics: FoundationDiagnostics = .init(), diagnosticIdentity: String? = nil) throws -> AppServices {
        var inspection = LiveProviderDiagnostics.make(vendors: vendors, base: foundationDiagnostics)
        guard RuntimeSafety.permitsRemote(environment: configuration.environment) else {
            inspection = inspection.recordingStartup(configurationRecords(vendors: vendors) + [.init(stage: .runtimeSafety, status: .skipped,
                code: "bootstrap.remote_suppressed", message: "Remote providers were not initialized in this runtime.")])
            return LocalServices.make(configuration: configuration, schema: schema, defaults: defaults, redaction: redaction,
                                      foundationDiagnostics: inspection)
        }
        if let cached {
            guard cached.configuration == configuration, vendorConfiguration == vendors, cachedSchema == schema,
                  cachedRedaction == redaction, analyticsIdentity == additionalAnalytics.map({ ObjectIdentifier($0) }),
                  cachedDiagnosticIdentity == diagnosticIdentity else {
                throw ProviderBootstrapError(records: [.init(stage: .validation, status: .failed,
                    code: "bootstrap.composition_conflict", message: "Another foundation composition has already been created.",
                    correction: "Create one immutable composition at the app entrypoint; pass it to all scenes.")])
            }
            return cached
        }
        var startup = configurationRecords(vendors: vendors)
        if startup.contains(where: { $0.status == .failed }) { throw ProviderBootstrapError(records: startup) }
        let logger = PulseLogger(redaction: redaction)
        let local = LocalTelemetryEngine(logger: logger)
        var diagnostics: [any DiagnosticsEngine] = [local]
        var sentry: SentryDiagnostics?
        if let dsn = vendors.sentryDSN {
            do {
                let engine = try SentryDiagnostics(dsn: dsn, configuration: configuration)
                sentry = engine; diagnostics.append(engine)
            }
            catch { throw startupError(provider: .sentry, prior: startup) }
        }
        let purchases: any PurchaseProviding
        var revenueCat: RevenueCatPurchases?
        if let key = vendors.revenueCatPublicKey {
            do {
                let adapter = try RevenueCatPurchases(key: key, configuration: configuration)
                revenueCat = adapter; purchases = adapter
            }
            catch { throw startupError(provider: .revenueCat, prior: startup) }
        }
        else { purchases = UnavailablePurchases() }
        for provider in [FoundationProvider.sentry, .revenueCat] {
            if provider == .sentry ? sentry != nil : revenueCat != nil {
                startup.append(.init(provider: provider, stage: .initialization, status: .succeeded,
                    code: "bootstrap.adapter_ready", message: "The adapter was constructed. SDK activation and remote delivery remain governed by runtime safety and preferences."))
            }
        }
        inspection = LiveProviderDiagnostics.make(vendors: vendors, base: foundationDiagnostics,
            purchases: revenueCat, sentry: sentry).recordingStartup(startup)
        let services = AppServices(configuration: configuration,
                                   telemetry: Telemetry(configuration: configuration, schema: schema,
                                                        analytics: [local] + additionalAnalytics, diagnostics: diagnostics,
                                                        redaction: redaction),
                                   logger: logger, purchases: purchases,
                                   developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults),
                                   foundationDiagnostics: inspection)
        cached = services; vendorConfiguration = vendors
        cachedSchema = schema; cachedRedaction = redaction
        analyticsIdentity = additionalAnalytics.map { ObjectIdentifier($0) }
        cachedDiagnosticIdentity = diagnosticIdentity
        return services
    }

    /// Pure local checks, also available when runtime safety suppresses remote initialization.
    public static func configurationRecords(vendors: LiveConfiguration) -> [ProviderStartupRecord] {
        var startup: [ProviderStartupRecord] = []
        for (provider, supplied, valid) in [
            (FoundationProvider.revenueCat, vendors.revenueCatPublicKey != nil, vendors.revenueCatPublicKey.map(RevenueCatProvider.isValidPublicKey) ?? false),
            (.sentry, vendors.sentryDSN != nil, vendors.sentryDSN.map(SentryProvider.isValidDSN) ?? false)
        ] {
            startup.append(.init(provider: provider, stage: .validation,
                status: supplied ? (valid ? .succeeded : .failed) : .skipped,
                code: supplied ? (valid ? "bootstrap.configuration_valid" : "bootstrap.configuration_invalid") : "bootstrap.configuration_absent",
                message: supplied ? (valid ? "The supplied client configuration passed local validation." : "The supplied client configuration failed local validation.") : "This optional provider has no supplied client configuration.",
                correction: supplied && !valid ? "Replace the target app's client configuration using its intended provider project." : nil))
        }
        return startup
    }

    /// Safe fallback retains configuration evidence rather than losing it during recovery.
    public static func makeRecovering(configuration: AppConfiguration, vendors: LiveConfiguration, schema: TelemetrySchema,
                                      defaults: UserDefaults = .standard,
                                      foundationDiagnostics: FoundationDiagnostics = .init(),
                                      redaction: RedactionPolicy = .init()) -> AppServices {
        do { return try make(configuration: configuration, vendors: vendors, schema: schema, defaults: defaults,
                             redaction: redaction, foundationDiagnostics: foundationDiagnostics) }
        catch {
            let records = recoveryRecords(for: error)
            let failed = Set(records.compactMap { $0.status == .failed ? $0.provider : nil })
            var inspection = LiveProviderDiagnostics.make(vendors: vendors, base: foundationDiagnostics, failedProviders: failed)
                .recordingStartup(records)
            inspection.bootstrapIssue = "Live provider bootstrap failed. Local services are active; remote delivery is unavailable."
            let services = LocalServices.make(configuration: configuration, schema: schema, purchases: UnavailablePurchases(),
                                              defaults: defaults, redaction: redaction, foundationDiagnostics: inspection)
            services.logger.error("Bootstrap configuration failed", error: error, category: "setup")
            return services
        }
    }

    private static func startupError(provider: FoundationProvider, prior: [ProviderStartupRecord]) -> ProviderBootstrapError {
        .init(records: prior + [.init(provider: provider, stage: .initialization, status: .failed,
            code: "bootstrap.initialization_conflict", message: "The adapter could not take ownership of its SDK initialization.",
            correction: "Remove competing SDK bootstrap calls and construct one foundation composition before using the provider.")])
    }

    public static func recoveryRecords(for error: any Error) -> [ProviderStartupRecord] {
        let records: [ProviderStartupRecord]
        if let bootstrap = error as? ProviderBootstrapError { records = bootstrap.records }
        else {
            let provider: FoundationProvider?
            switch error as? BootstrapFailure {
            case .invalidFirebaseConfiguration: provider = .firebase
            case .invalidRevenueCatKey: provider = .revenueCat
            case .invalidSentryDSN: provider = .sentry
            default: provider = nil
            }
            records = [.init(provider: provider, stage: .validation, status: .failed,
                code: "bootstrap.configuration_failure", message: "The composition could not validate or initialize its provider configuration.",
                correction: "Confirm the target app's client configuration and remove competing SDK bootstrap calls.")]
        }
        return records + [.init(stage: .recovery, status: .succeeded, code: "bootstrap.local_recovery",
            message: "Local services are active. Startup records preserve which stage failed; any already initialized SDK remains separately visible.")]
    }
}
