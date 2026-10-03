import MZAppFoundation
import MZAppFoundationRevenueCat
import MZAppFoundationSentry

@MainActor public enum LiveProviderDiagnostics {
    /// Passive inspection. Creating snapshots never initializes SDKs or performs network requests.
    public static func make(vendors: LiveConfiguration, base: FoundationDiagnostics = .init(),
                            bootstrapFailure: Bool = false, failedProviders: Set<FoundationProvider> = [], purchases: RevenueCatPurchases? = nil,
                            sentry: SentryDiagnostics? = nil) -> FoundationDiagnostics {
        let revenueCat = RevenueCatProvider.diagnostics(publicKey: vendors.revenueCatPublicKey,
            project: vendors.revenueCatProject, base: base, bootstrapFailure: bootstrapFailure || failedProviders.contains(.revenueCat), purchases: purchases)
        return SentryProvider.diagnostics(dsn: vendors.sentryDSN, project: vendors.sentryProject,
            base: revenueCat, bootstrapFailure: bootstrapFailure || failedProviders.contains(.sentry), engine: sentry)
    }
}
