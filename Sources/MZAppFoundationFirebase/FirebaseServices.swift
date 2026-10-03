import Foundation
import MZAppFoundation
import MZAppFoundationLive
import MZAppFoundationLocal
@_exported import MZAppFoundationFirebaseAnalytics

/// Compatibility composition with Firebase, RevenueCat and Sentry. For Firebase-only apps,
/// use the independent MZAppFoundationFirebaseAnalytics product and inject its engine directly.
@MainActor public enum FirebaseServices {
    private static var cached: AppServices?
    private static var cachedPath: String?
    private static var cachedVendors: LiveConfiguration?
    private static var cachedSchema: TelemetrySchema?
    private static var cachedProjectName: String?

    public static func make(configuration: AppConfiguration, vendors: LiveConfiguration, schema: TelemetrySchema,
                            googleServiceInfoPath: String?, defaults: UserDefaults = .standard,
                            firebaseProjectName: String? = nil,
                            foundationDiagnostics: FoundationDiagnostics = .init()) throws -> AppServices {
        var inspection = FirebaseProvider.diagnostics(googleServiceInfoPath: googleServiceInfoPath,
            projectName: firebaseProjectName, base: foundationDiagnostics)
        guard RuntimeSafety.permitsRemote(environment: configuration.environment) else {
            return LocalServices.make(configuration: configuration, schema: schema, defaults: defaults,
                foundationDiagnostics: LiveProviderDiagnostics.make(vendors: vendors, base: inspection)
                    .recordingStartup(LiveServices.configurationRecords(vendors: vendors) + [.init(stage: .runtimeSafety, status: .skipped, code: "bootstrap.remote_suppressed",
                        message: "Remote providers were not initialized in this runtime.")]))
        }
        if let cached {
            guard cached.configuration == configuration, cachedVendors == vendors,
                  cachedPath == googleServiceInfoPath, cachedSchema == schema,
                  cachedProjectName == firebaseProjectName else {
                throw ProviderBootstrapError(records: [.init(stage: .validation, status: .failed,
                    code: "bootstrap.composition_conflict", message: "A different Firebase composition has already been created.",
                    correction: "Create one immutable composition at the app entrypoint and share it across scenes.")])
            }
            return cached
        }
        var analytics: [any AnalyticsEngine] = []
        #if os(iOS)
        if let path = googleServiceInfoPath {
            let file = FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: path)
            guard file.state == .configured else {
                throw ProviderBootstrapError(records: [.init(provider: .firebase, stage: .validation, status: .failed,
                    code: "firebase.configuration_invalid", message: "The supplied Firebase configuration is missing or invalid for this app.",
                    correction: "Add this app's GoogleService-Info.plist and ensure its BUNDLE_ID and required identifiers match the build.")])
            }
            let engine: FirebaseAnalyticsEngine
            do { engine = try FirebaseAnalyticsEngine(configuration: configuration, path: path) }
            catch {
                throw ProviderBootstrapError(records: [.init(provider: .firebase, stage: .initialization, status: .failed,
                    code: "firebase.initialization_conflict", message: "The Firebase adapter could not take ownership of initialization.",
                    correction: "Remove competing FirebaseApp.configure calls and initialize Firebase through one composition.")])
            }
            analytics.append(engine)
            inspection = FirebaseProvider.diagnostics(googleServiceInfoPath: path, projectName: firebaseProjectName,
                engine: engine, base: foundationDiagnostics).recordingStartup([
                    .init(provider: .firebase, stage: .validation, status: .succeeded,
                        code: "firebase.configuration_valid", message: "The Firebase client identifiers match this app."),
                    .init(provider: .firebase, stage: .initialization, status: .succeeded,
                        code: "firebase.adapter_ready", message: "The adapter is ready. Firebase initializes when analytics delivery is enabled.")])
        }
        #endif
        let services = try LiveServices.make(configuration: configuration, vendors: vendors, schema: schema,
            additionalAnalytics: analytics, defaults: defaults, foundationDiagnostics: inspection,
            diagnosticIdentity: "firebase:" + (googleServiceInfoPath ?? "") + "\u{0}" + (firebaseProjectName ?? ""))
        cached = services; cachedPath = googleServiceInfoPath; cachedVendors = vendors; cachedSchema = schema
        cachedProjectName = firebaseProjectName
        return services
    }

    public static func makeRecovering(configuration: AppConfiguration, vendors: LiveConfiguration, schema: TelemetrySchema,
                                      googleServiceInfoPath: String?, defaults: UserDefaults = .standard,
                                      firebaseProjectName: String? = nil,
                                      foundationDiagnostics: FoundationDiagnostics = .init()) -> AppServices {
        do {
            return try make(configuration: configuration, vendors: vendors, schema: schema,
                googleServiceInfoPath: googleServiceInfoPath, defaults: defaults,
                firebaseProjectName: firebaseProjectName, foundationDiagnostics: foundationDiagnostics)
        } catch {
            let records = LiveServices.recoveryRecords(for: error)
            let failed = Set(records.compactMap { $0.status == .failed ? $0.provider : nil })
            var inspection = LiveProviderDiagnostics.make(vendors: vendors,
                base: FirebaseProvider.diagnostics(googleServiceInfoPath: googleServiceInfoPath,
                    bootstrapFailure: failed.contains(.firebase), projectName: firebaseProjectName,
                    base: foundationDiagnostics), failedProviders: failed).recordingStartup(records)
            inspection.bootstrapIssue = "Provider bootstrap failed. Local services are active; inspect startup records for the failed provider and recovery steps."
            let services = LocalServices.make(configuration: configuration, schema: schema, purchases: UnavailablePurchases(),
                defaults: defaults, foundationDiagnostics: inspection)
            services.logger.error("Bootstrap configuration failed", error: error, category: "setup")
            return services
        }
    }

    public static func diagnostics(googleServiceInfoPath: String?, bootstrapFailure: Bool = false,
                                   projectName: String? = nil) -> FoundationDiagnostics {
        FirebaseProvider.diagnostics(googleServiceInfoPath: googleServiceInfoPath,
            bootstrapFailure: bootstrapFailure, projectName: projectName)
    }
}
