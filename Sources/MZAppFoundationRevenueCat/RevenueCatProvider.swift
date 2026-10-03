import Foundation
import MZAppFoundation
import RevenueCat

@MainActor public enum RevenueCatProvider {
    public static func isValidPublicKey(_ key: String) -> Bool { key.hasPrefix("appl_") && key.count > 10 }

    public static func diagnostics(publicKey: String?, project: ProviderProjectIdentity = .init(),
                                   base: FoundationDiagnostics = .init(), bootstrapFailure: Bool = false,
                                   purchases: RevenueCatPurchases? = nil) -> FoundationDiagnostics {
        let inspection = base.replacing(.revenueCat) { context in
            let valid = publicKey.map(isValidPublicKey) ?? false
            let state: ProviderConfigurationState = publicKey == nil ? .notConfigured : (valid ? .configured : .invalid)
            let ownership: ProviderOwnership = RevenueCatPurchases.ownership == .notInitialized ? .notInitialized
                : (purchases?.ownsRunningSDK == true ? .ownedByComposition : .external)
            let runtime: ProviderRuntimeState = bootstrapFailure ? .failed
                : (!context.remoteAllowed && valid ? .suppressed
                    : (ownership == .notInitialized ? .notInitialized : .initialized))
            return ProviderSnapshot(provider: .revenueCat, sdkVersion: Purchases.frameworkVersion,
                versionSource: "SDK runtime", configuration: state, runtime: runtime,
                delivery: bootstrapFailure ? .unavailable : (!context.remoteAllowed
                    ? context.delivery(configured: valid, preference: true) : (valid && ownership == .ownedByComposition ? .enabled : .unavailable)),
                details: project.details + [.init("key", label: "Public SDK key",
                    value: publicKey == nil ? "Missing" : (valid ? "Present · hidden" : "Invalid · hidden"))],
                explanation: "Project labels are supplied by the app. RevenueCat does not expose its dashboard project identity from the running SDK. Initialization does not verify purchases or the product catalog.",
                identityAudit: .init(supplied: project, ownership: ownership))
        }
        guard let purchases else { return inspection }
        return inspection.replacing(purchaseDiagnostics: { [weak purchases] in purchases?.diagnosticsSnapshot })
            .adding(action: .init(id: "revenuecat.refresh_diagnostics", title: "Refresh customer information and offerings",
                provider: .revenueCat) { [weak purchases] context in
                guard context.remoteAllowed, let purchases, purchases.ownsRunningSDK else {
                    return .init(status: .unavailable, code: "revenuecat.read_unavailable",
                        message: "Purchase diagnostics require this composition's RevenueCat provider and a runtime that permits remote requests.")
                }
                return await purchases.refreshDiagnostics()
            })
    }
}
