import MZAppFoundation
import SwiftUI

struct FoundationTelemetryView: View {
    let services: AppServices
    var body: some View {
        List {
            Section {
                DiagnosticValueRow("Analytics preference", value: services.telemetry.preferences.analytics ? "On" : "Off")
                DiagnosticValueRow("Diagnostics preference", value: services.telemetry.preferences.diagnostics ? "On" : "Off")
                Text("Adapter outcomes count each engine separately. Blocking reasons can overlap. Accepted records and submitted breadcrumbs do not prove backend delivery.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            counterSection("Analytics", counters: services.telemetry.counters.analytics)
            counterSection("Diagnostics", counters: services.telemetry.counters.diagnostics)
            counterSection("Breadcrumbs", counters: services.telemetry.counters.breadcrumbs)
            Section { Button("Reset counters", role: .destructive) { services.telemetry.resetCounters() } }
        }
        .navigationTitle("Telemetry counters")
        .accessibilityIdentifier("mz.foundation.telemetry")
    }

    private func counterSection(_ title: String, counters: TelemetryChannelCounters) -> some View {
        Section(title) {
            DiagnosticValueRow("Attempts", value: String(counters.attempts))
            DiagnosticValueRow("Schema rejected", value: String(counters.schemaRejected))
            DiagnosticValueRow("Properties filtered", value: String(counters.filteredProperties))
            DiagnosticValueRow("Preference blocked", value: String(counters.preferenceBlocked))
            DiagnosticValueRow("Runtime blocked", value: String(counters.runtimeBlocked))
            DiagnosticValueRow("No engines", value: String(counters.noEngines))
            DiagnosticValueRow("Recorded locally", value: String(counters.recordedLocal))
            DiagnosticValueRow("Accepted by remote adapter", value: String(counters.submittedRemote))
            DiagnosticValueRow("Breadcrumb submissions", value: String(counters.submitted))
            DiagnosticValueRow("Ignored", value: String(counters.ignored))
            DiagnosticValueRow("Failed", value: String(counters.failed))
        }
    }
}
