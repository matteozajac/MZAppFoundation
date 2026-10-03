import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct DeveloperQATests {
    private func configuration(_ environment: AppEnvironment = .local) -> AppConfiguration {
        .init(bundleIdentifier: "qa.test", urlScheme: "qa", environment: environment)
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "mz.qa.tests." + UUID().uuidString)! }

    @Test(arguments: [AppEnvironment.production, .internalTesting])
    func remoteCompositionsCannotBeReplaced(environment: AppEnvironment) {
        #expect(throws: DeveloperQAFailure.forbiddenRuntime) {
            try DeveloperQAServices.make(scenario: .pendingPurchase, configuration: configuration(environment),
                                        schema: .init(events: [:]), defaults: defaults())
        }
    }

    @Test(arguments: DeveloperQAScenario.allCases)
    func allScenariosKeepAuthoritativeAccessEmpty(scenario: DeveloperQAScenario) async throws {
        let services = try DeveloperQAServices.make(scenario: scenario, configuration: configuration(),
                                                  schema: .init(events: [:]), defaults: defaults())
        #expect(services.purchases.cachedState?.active.isEmpty == true)
        #expect(services.purchases is DeveloperQAPurchases)
        #expect(services.providerSnapshots.allSatisfy { $0.runtime == .notLinked && $0.delivery == .unavailable })
        if scenario == .missingConfiguration {
            let firebase = try #require(services.providerSnapshots.first { $0.provider == .firebase })
            #expect(firebase.configuration == .missing)
            #expect(firebase.details.contains { $0.label == "GoogleService-Info.plist" && $0.value == "Simulated missing file" })
        }
        if scenario == .offline || scenario == .missingConfiguration {
            let failure: PurchaseFailure = scenario == .offline ? .network : .unavailable
            await #expect(throws: failure) { try await services.purchases.offers(offeringID: nil) }
            await #expect(throws: failure) { try await services.purchases.restore() }
        } else {
            let offers = try await services.purchases.offers(offeringID: nil)
            let offer = try #require(offers.first)
            #expect(offer.title.contains("Simulated") && offer.productID.hasPrefix("simulated."))
            let result = try await services.purchases.purchase(offer)
            if scenario == .pendingPurchase { #expect(result == .pending) }
            if scenario == .verificationFailed { #expect(result == .purchased(.init(verificationFailed: true))) }
            #expect(services.purchases.cachedState?.active.isEmpty == true)
        }
    }

    @Test func launchArgumentProfilesAreExplicitAndBounded() {
        #expect(DeveloperQAScenario.fromLaunchArguments(["--foundation-qa", "offline"]) == .offline)
        #expect(DeveloperQAScenario.fromLaunchArguments(["--foundation-qa"]) == nil)
        #expect(DeveloperQAScenario.fromLaunchArguments(["--foundation-qa", "unrecognized"]) == nil)
    }
}
