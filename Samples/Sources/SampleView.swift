import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

struct SampleView: View {
    let services: AppServices
    @State private var count = 0
    @State private var purchaseStatus = "No entitlement"
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("One foundation. Every app.", systemImage: "square.stack.3d.up.fill")
                        .font(.title2.bold()).padding(.vertical, 12)
                    Text("Analytics, purchases, and diagnostics behind interfaces you can test.")
                        .foregroundStyle(.secondary)
                }
                Section("Analytics") {
                    LabeledContent("Recorded actions", value: String(count))
                    Button("Record an action", systemImage: "waveform.path") {
                        count += 1
                        services.analytics.track(TelemetryEvent("sample_action", properties: ["count": .integer(count)]))
                    }
                    Toggle("Remote analytics", isOn: Binding(get: { services.telemetry.preferences.analytics }, set: {
                        var preferences = services.telemetry.preferences; preferences.analytics = $0
                        services.telemetry.updatePreferences(preferences)
                    }))
                    Toggle("Crash reporting", isOn: Binding(get: { services.telemetry.preferences.diagnostics }, set: {
                        var preferences = services.telemetry.preferences; preferences.diagnostics = $0
                        services.telemetry.updatePreferences(preferences)
                    }))
                }
                Section("Purchases") {
                    Text(purchaseStatus).foregroundStyle(.secondary)
                    Button("Try purchase") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                guard let offer = try await services.purchases.offers(offeringID: nil).first else {
                                    purchaseStatus = "No offering configured"; return
                                }
                                switch try await services.purchases.purchase(offer) {
                                case .purchased: purchaseStatus = "Purchase completed"
                                case .cancelled: purchaseStatus = "Cancelled"
                                case .pending: purchaseStatus = "Awaiting approval"
                                }
                            } catch { purchaseStatus = "Purchases unavailable" }
                        }
                    }.disabled(busy)
                    Button("Restore purchases") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                let state = try await services.purchases.restore()
                                purchaseStatus = state.active.isEmpty ? "Nothing to restore" : "Access restored"
                            } catch { purchaseStatus = "Restore unavailable" }
                        }
                    }.disabled(busy)
                }
                Section("Developer tools") {
                    Button("Record sample error") {
                        services.logger.error("Sample model loading failed", error: SampleLoadingError(),
                                              category: "model", metadata: ["model_id": .string("sample")])
                    }.accessibilityIdentifier("sample.error")
                    Toggle("Developer mode", isOn: Binding(get: { services.developerOptions.isEnabled },
                                                            set: { services.developerOptions.setEnabled($0) }))
                    Button("Open console", systemImage: "ladybug") { services.developerOptions.requestConsole() }
                        .disabled(!services.developerOptions.isEnabled)
                    #if os(iOS)
                    FoundationSettingsLink(services: services,
                        pages: FoundationDeveloperTools.pages(services: services, reporting: SampleBootstrap.reporting))
                    #else
                    FoundationSettingsLink(services: services, pages: FoundationDeveloperTools.pages(services: services))
                    #endif
                }
                #if os(iOS)
                if services.developerOptions.isEnabled {
                    DeveloperReportingSettings(reporting: SampleBootstrap.reporting)
                }
                #endif
                Section {
                    Text(services.configuration.environment == .local
                         ? "Local composition · simulated purchases · no remote SDK delivery"
                         : "Device composition · provider credentials are not configured in this sample")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("MZ Foundation")
            .tint(.indigo)
        }
    }
}

struct SampleLoadingError: LoggableError {
    var logMessage: String { "Model weights are unavailable" }
}
