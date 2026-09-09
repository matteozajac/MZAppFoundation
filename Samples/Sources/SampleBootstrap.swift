import Foundation
import MZAppFoundation
import MZAppFoundationLocal
#if !MZ_LOCAL && !targetEnvironment(simulator)
import MZAppFoundationLive
#if os(iOS)
import MZAppFoundationFirebase
#endif
#endif

@MainActor enum SampleBootstrap {
    static func make() -> AppServices {
        let environment: AppEnvironment
        #if MZ_LOCAL || DEBUG || targetEnvironment(simulator)
        environment = .local
        #elseif MZ_INTERNAL
        environment = .internalTesting
        #else
        environment = .production
        #endif
        let configuration = AppConfiguration(bundleIdentifier: Bundle.main.bundleIdentifier ?? "sample",
                                             urlScheme: "mzsample", environment: environment)
        let schema = TelemetrySchema(events: ["sample_action": ["count"]])
        #if MZ_LOCAL || targetEnvironment(simulator)
        let mock = MockPurchases(offers: [PurchaseOffer(id: "demo/lifetime", offeringID: "demo", productID: "demo.premium",
                                                       title: "Demo Premium", localizedPrice: "Simulated")])
        mock.purchaseResult = .success(.purchased(.init(active: ["premium"])))
        mock.restoreResult = .success(.init(active: ["premium"]))
        return LocalServices.make(configuration: configuration, schema: schema, purchases: mock)
        #else
        // Samples intentionally contain no provider credentials. Configure a real consumer using the setup skill.
        do {
            #if os(iOS)
            return try FirebaseServices.make(configuration: configuration, vendors: .init(), schema: schema,
                                             googleServiceInfoPath: nil)
            #else
            return try LiveServices.make(configuration: configuration, vendors: .init(), schema: schema)
            #endif
        } catch {
            let services = LocalServices.make(configuration: configuration, schema: schema, purchases: UnavailablePurchases())
            services.logger.log(LogEntry("bootstrap_failed", level: .error))
            return services
        }
        #endif
    }
}
