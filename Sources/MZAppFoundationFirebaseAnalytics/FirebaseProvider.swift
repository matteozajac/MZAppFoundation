import Foundation
import MZAppFoundation
#if os(iOS)
import FirebaseCore
#endif

@MainActor public enum FirebaseProvider {
    public static func diagnostics(googleServiceInfoPath: String?, bootstrapFailure: Bool = false,
                                   projectName: String? = nil, base: FoundationDiagnostics = .init(),
                                   ownsRunningSDK: @escaping @MainActor () -> Bool = { false },
                                   managesAnalytics: @escaping @MainActor () -> Bool = { false }) -> FoundationDiagnostics {
        base.replacing(.firebase) { context in
            let file = FirebaseConfigurationInspection.inspect(bundleIdentifier: context.configuration.bundleIdentifier,
                                                               path: googleServiceInfoPath)
            let value: (String) -> String? = { id in file.details.first { $0.id == id }?.value }
            let supplied = ProviderProjectIdentity(name: projectName, projectID: value("PROJECT_ID"), appID: value("GOOGLE_APP_ID"))
            #if os(iOS)
            let version: String? = FirebaseVersion()
            let ownership: ProviderOwnership = FirebaseAnalyticsEngine.ownership == .notInitialized ? .notInitialized
                : (ownsRunningSDK() ? .ownedByComposition : .external)
            let running = FirebaseAnalyticsEngine.runningIdentity
            let runtime: ProviderRuntimeState = bootstrapFailure ? .failed
                : (!context.remoteAllowed && file.state == .configured ? .suppressed
                    : (ownership == .notInitialized ? .notInitialized : .initialized))
            let delivery = bootstrapFailure ? ProviderDeliveryState.unavailable
                : (!context.remoteAllowed || !context.preferences.analytics
                    ? context.delivery(configured: file.state == .configured, preference: context.preferences.analytics)
                    : (file.state == .configured && (ownership == .ownedByComposition || managesAnalytics()) ? .enabled : .unavailable))
            let details = [ProviderDetail("projectName", label: "Project name", value: projectName ?? "Not supplied by app")] + file.details + [
                ProviderDetail("coreVersion", label: "FirebaseCore version", value: version ?? "Unknown"),
                ProviderDetail("analyticsVersion", label: "FirebaseAnalytics package pin", value: FoundationVersion.resolvedPackageVersions["firebase-ios-sdk"] ?? "Unknown")]
            #else
            let version: String? = nil
            let runtime = ProviderRuntimeState.unsupported
            let delivery = ProviderDeliveryState.unavailable
            let ownership = ProviderOwnership.notInitialized
            let running: ProviderProjectIdentity? = nil
            let details = [ProviderDetail("projectName", label: "Project name", value: projectName ?? "Not supplied by app")] + file.details
            #endif
            return ProviderSnapshot(provider: .firebase, sdkVersion: version, versionSource: version == nil ? nil : "FirebaseCore runtime",
                configuration: file.state, runtime: runtime, delivery: delivery, details: details,
                explanation: file.explanation + " Firebase Analytics is supported on iOS. The running identity is read from FirebaseApp options; ownership is attributed separately.",
                identityAudit: .init(supplied: supplied, running: running, ownership: ownership))
        }
    }

    #if os(iOS)
    public static func diagnostics(googleServiceInfoPath: String?, projectName: String? = nil,
                                   engine: FirebaseAnalyticsEngine, base: FoundationDiagnostics = .init()) -> FoundationDiagnostics {
        diagnostics(googleServiceInfoPath: googleServiceInfoPath, projectName: projectName, base: base,
            ownsRunningSDK: { [weak engine] in engine?.ownsRunningSDK == true },
            managesAnalytics: { [weak engine] in engine?.managesAnalytics == true })
            .adding(action: .init(id: "firebase.submit_verification", title: "Submit a tagged Firebase event", provider: .firebase) {
                [weak engine] context in
                guard let engine else { return .init(status: .unavailable, code: "firebase.provider_unavailable", message: "The Firebase provider is unavailable.") }
                return engine.submitVerification(context: context)
            })
    }
    #endif
}
