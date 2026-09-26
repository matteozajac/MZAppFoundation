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
        let services = LocalServices.make(configuration: configuration, schema: schema, purchases: mock)
        if ProcessInfo.processInfo.arguments.contains("--logging-demo") {
            services.logger.error("Sample model loading failed", error: SampleLoadingError(),
                                  category: "model", metadata: ["model_id": .string("sample")])
            services.developerOptions.setEnabled(true)
            services.developerOptions.requestConsole()
        }
        return services
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
            services.logger.error("Bootstrap failed", error: error)
            return services
        }
        #endif
    }
}
