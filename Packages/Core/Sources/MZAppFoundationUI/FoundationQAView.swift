import MZAppFoundation
import SwiftUI

/// Runs isolated mock services. It never replaces the host's services or contacts a live SDK.
struct FoundationQAView: View {
    let services: AppServices
    @State private var scenario = DeveloperQAScenario.missingConfiguration
    @State private var preview: AppServices?
    @State private var result = "Select a scenario and run a check."
    @State private var requested: String?

    var body: some View {
        List {
            Section {
                Label("Simulated services", systemImage: "testtube.2").font(.headline)
                Text("This isolated local composition uses mocks. Its outcomes do not authorize purchases or modify the running app's services.")
                Picker("Scenario", selection: $scenario) {
                    ForEach(DeveloperQAScenario.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            if let preview {
                let activeEntitlements = preview.purchases.cachedState?.active.sorted() ?? []
                Section("Provider state") {
                    ForEach(preview.providerSnapshots) { FoundationProviderRow(snapshot: $0) }
                }
                Section("Mock checks") {
                    Button("Fetch mock offers") { requested = "offers" }
                    Button("Try mock purchase") { requested = "purchase" }
                    Button("Refresh mock entitlements") { requested = "refresh" }
                    DiagnosticValueRow("Outcome", value: result)
                    DiagnosticValueRow("Granted entitlements", value: activeEntitlements.isEmpty ? "None" : activeEntitlements.joined(separator: ", "))
                }.disabled(requested != nil)
            } else { Text("QA scenarios are available only in a local debug/test composition.") }
        }
        .navigationTitle("Local QA scenarios")
        .task(id: scenario) { prepare() }
        .task(id: requested) { await runCheck() }
    }

    private func prepare() {
        let name = "mz.foundation.qa." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        preview = try? DeveloperQAServices.make(scenario: scenario, configuration: services.configuration,
                                               schema: .init(events: [:]), defaults: defaults)
        result = "Ready · " + scenario.rawValue
        services.telemetry.timeline.record(.mockScenarioChanged, category: .mockScenario, status: .updated)
    }
    private func runCheck() async {
        guard let requested, let preview, services.developerOptions.isEnabled else { return }
        defer { self.requested = nil }
        do {
            switch requested {
            case "offers": result = "Mock offers: " + String(try await preview.purchases.offers(offeringID: nil).count)
            case "purchase":
                if let offer = try await preview.purchases.offers(offeringID: nil).first {
                    switch try await preview.purchases.purchase(offer) {
                    case .pending: result = "Mock purchase pending"
                    case .cancelled: result = "Mock purchase cancelled"
                    case .purchased: result = "Mock purchase response received"
                    }
                } else { result = "No mock offer available" }
            default:
                let state = try await preview.purchases.refresh()
                result = state.verificationFailed ? "Mock verification failed · no access" : "Mock entitlements refreshed"
            }
        } catch { result = "Mock operation unavailable · " + scenario.rawValue }
    }
}
