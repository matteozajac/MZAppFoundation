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
    private static weak var activeServices: AppServices?
    #if os(iOS)
    static let reporting: DeveloperReporting = {
        let reporting = DeveloperReporting(archivePrefix: "mzsample", diagnostics: {
            guard let services = activeServices else { throw PurchaseFailure.unavailable }
            return try services.diagnosticExport().jsonData()
        })
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--logging-demo") {
            reporting.recordsRecentActivity = false
        }
        return reporting
    }()
    #endif
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
                                             urlScheme: "mzsample", environment: environment,
                                             version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                                             build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                                             developerLinkHost: "sample")
        let schema = TelemetrySchema(events: ["sample_action": ["count"]])
        #if MZ_LOCAL || targetEnvironment(simulator)
        let mock = MockPurchases(offers: [PurchaseOffer(id: "demo/lifetime", offeringID: "demo", productID: "demo.premium",
                                                       title: "Demo Premium", localizedPrice: "Simulated")])
        mock.purchaseResult = .success(.purchased(.init(active: ["premium"])))
        mock.restoreResult = .success(.init(active: ["premium"]))
        let scenario = DeveloperQAScenario.fromLaunchArguments(ProcessInfo.processInfo.arguments)
        let purchases: any PurchaseProviding
        var inventory: FoundationDiagnostics
        if let scenario, (try? DeveloperQAServices.configure(mock: mock, scenario: scenario, configuration: configuration)) != nil {
            purchases = DeveloperQAPurchases(mock: mock, scenario: scenario)
            inventory = DeveloperQAServices.diagnostics(scenario: scenario)
        } else {
            purchases = mock
            inventory = .init()
        }
        if ProcessInfo.processInfo.arguments.contains("--foundation-expanded-demo") {
            inventory.expectations = [.init(.firebase, expectation: .required, environments: [.local])]
            inventory.additionalInspections = [.init(id: "sampleService") { context in
                .init(id: "sampleService", title: "Sample service", summary: "SDK-free sample composition",
                    details: [.init("environment", label: "Environment", value: context.configuration.environment.rawValue)],
                    exportableDetailIDs: ["environment"])
            }]
        }
        let services = LocalServices.make(configuration: configuration, schema: schema, purchases: purchases,
                                          foundationDiagnostics: inventory)
        if scenario != nil { services.developerOptions.enableUntilAppCloses() }
        if ProcessInfo.processInfo.arguments.contains("--foundation-settings-demo") {
            services.developerOptions.setEnabled(true)
        }
        if ProcessInfo.processInfo.arguments.contains("--logging-demo") {
            services.logger.error("Sample model loading failed", error: SampleLoadingError(),
                                  category: "model", metadata: ["model_id": .string("sample")])
            services.developerOptions.setEnabled(true)
            services.developerOptions.requestConsole()
        }
        activeServices = services
        return services
        #else
        // Samples intentionally contain no provider credentials. Configure a real consumer using the setup skill.
        #if os(iOS)
        let services = FirebaseServices.makeRecovering(configuration: configuration, vendors: .init(), schema: schema,
                                               googleServiceInfoPath: nil)
        #else
        let services = LiveServices.makeRecovering(configuration: configuration, vendors: .init(), schema: schema)
        #endif
        activeServices = services
        return services
        #endif
    }
}
