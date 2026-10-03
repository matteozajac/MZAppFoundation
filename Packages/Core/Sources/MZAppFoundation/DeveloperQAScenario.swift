import Foundation

public enum DeveloperQAScenario: String, CaseIterable, Identifiable, Codable, Sendable {
    case missingConfiguration = "Missing configuration"
    case offline = "Offline"
    case pendingPurchase = "Pending purchase"
    case verificationFailed = "Verification failed"
    public var id: String { rawValue }
    public var explanation: String {
        switch self {
        case .missingConfiguration: "Simulated missing providers. Purchases are unavailable."
        case .offline: "Simulated purchase networking failure. No network requests are made."
        case .pendingPurchase: "Simulated pending transaction. No entitlement is granted."
        case .verificationFailed: "Simulated unverified purchase state. Access stays denied."
        }
    }
    public static func fromLaunchArguments(_ arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--foundation-qa"), index + 1 < arguments.count else { return nil }
        return switch arguments[index + 1] {
        case "missing-configuration": .missingConfiguration
        case "offline": .offline
        case "pending-purchase": .pendingPurchase
        case "verification-failed": .verificationFailed
        default: nil
        }
    }
}

public enum DeveloperQAFailure: Error, Equatable, Sendable { case forbiddenRuntime }

/// Builds a separate, explicitly simulated composition. It never changes live SDK singleton state.
@MainActor public enum DeveloperQAServices {
    public static func isAvailable(configuration: AppConfiguration) -> Bool {
        guard configuration.environment == .local else { return false }
        #if DEBUG || targetEnvironment(simulator)
        return true
        #else
        let process = ProcessInfo.processInfo
        return process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || NSClassFromString("XCTestCase") != nil
            || process.environment["XCTestConfigurationFilePath"] != nil
        #endif
    }

    public static func make(scenario: DeveloperQAScenario, configuration: AppConfiguration,
                            schema: TelemetrySchema, defaults: UserDefaults = .standard) throws -> AppServices {
        guard isAvailable(configuration: configuration) else { throw DeveloperQAFailure.forbiddenRuntime }
        let mock = MockPurchases()
        try configure(mock: mock, scenario: scenario, configuration: configuration)
        return AppServices(configuration: configuration,
                           telemetry: Telemetry(configuration: configuration, schema: schema,
                                                analytics: [NoopAnalyticsEngine()], diagnostics: [NoopDiagnosticsEngine()]),
                           logger: RecordingLogger(), purchases: DeveloperQAPurchases(mock: mock, scenario: scenario),
                           developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults),
                           foundationDiagnostics: diagnostics(scenario: scenario))
    }

    /// Enables an app's SDK-free local logger (including Pulse) to keep its existing composition.
    public static func configure(mock: MockPurchases, scenario: DeveloperQAScenario,
                                 configuration: AppConfiguration) throws {
        guard isAvailable(configuration: configuration) else { throw DeveloperQAFailure.forbiddenRuntime }
        mock.send(.init(verificationFailed: scenario == .verificationFailed))
        mock.availableOffers = scenario == .missingConfiguration || scenario == .offline ? [] : [
            .init(id: "simulated/qa", offeringID: "simulated", productID: "simulated.qa",
                  title: "Simulated QA purchase", localizedPrice: "Simulated — no charge")
        ]
        switch scenario {
        case .missingConfiguration:
            mock.purchaseResult = .failure(.unavailable); mock.refreshResult = .failure(.unavailable)
            mock.restoreResult = .failure(.unavailable)
        case .offline:
            mock.purchaseResult = .failure(.network); mock.refreshResult = .failure(.network)
            mock.restoreResult = .failure(.network)
        case .pendingPurchase:
            mock.purchaseResult = .success(.pending); mock.refreshResult = .success(.init())
            mock.restoreResult = .success(.init())
        case .verificationFailed:
            let denied = EntitlementState(verificationFailed: true)
            mock.purchaseResult = .success(.purchased(denied)); mock.refreshResult = .success(denied)
            mock.restoreResult = .success(denied)
        }
    }

    public static func diagnostics(scenario: DeveloperQAScenario) -> FoundationDiagnostics {
        let inspections = Dictionary(uniqueKeysWithValues: FoundationProvider.allCases.map { provider in
            (provider, { @MainActor (_: ProviderInspectionContext) in
                ProviderSnapshot(provider: provider,
                                 configuration: scenario == .missingConfiguration ? .missing : .notConfigured,
                                 runtime: .notLinked, delivery: .unavailable,
                                 details: [.init("qa.scenario", label: "Simulated QA scenario", value: scenario.rawValue)]
                                    + (provider == .firebase && scenario == .missingConfiguration
                                        ? [.init("firebase.file", label: "GoogleService-Info.plist", value: "Simulated missing file")] : []),
                                 explanation: scenario.explanation + " This composition has no remote adapters.")
            } as FoundationDiagnostics.Inspection)
        })
        return FoundationDiagnostics(inspections: inspections)
    }
}

/// Keeps the offline and missing-configuration offers path faithful without changing MockPurchases semantics.
@MainActor public final class DeveloperQAPurchases: PurchaseProviding {
    private let mock: MockPurchases
    public let scenario: DeveloperQAScenario
    public init(mock: MockPurchases, scenario: DeveloperQAScenario) {
        self.mock = mock; self.scenario = scenario
    }
    public var cachedState: EntitlementState? { mock.cachedState }
    public func updates() -> AsyncStream<EntitlementState> { mock.updates() }
    public func offers(offeringID: String?) async throws -> [PurchaseOffer] {
        if scenario == .offline { throw PurchaseFailure.network }
        if scenario == .missingConfiguration { throw PurchaseFailure.unavailable }
        return try await mock.offers(offeringID: offeringID)
    }
    public func refresh() async throws -> EntitlementState { try await mock.refresh() }
    public func purchase(_ offer: PurchaseOffer) async throws -> PurchaseOutcome { try await mock.purchase(offer) }
    public func restore() async throws -> EntitlementState { try await mock.restore() }
    public func identify(_ userID: String?) async throws -> EntitlementState {
        // Identity is intentionally inert in QA and cannot expose or mutate a real user ID.
        try await mock.refresh()
    }
}
