import MZAppFoundation
import SwiftUI

struct FoundationAccessView: View {
    let options: DeveloperOptions
    var body: some View {
        List {
            Section("Current access") {
                DiagnosticValueRow("Preference key", value: DeveloperOptions.preferenceKey)
                DiagnosticValueRow("Activation", value: options.activationSource.rawValue)
                DiagnosticValueRow("Expires", value: options.expiresAt?.formatted() ?? "No timed expiry")
                Text("The key name is shared across apps and platforms. Each app keeps its own value in its defaults store.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Enable until app closes") { options.enableUntilAppCloses() }
                Button("Enable for 15 minutes") { options.enable(for: 15 * 60) }
                Button("Enable for 1 hour") { options.enable(for: 60 * 60) }
                Button("Keep enabled after relaunch") { options.setEnabled(true) }
                Button("Disable developer options", role: .destructive) { options.setEnabled(false) }
            } header: { Text("Duration") } footer: {
                Text("Temporary access replaces saved access with Off for the next launch. It never changes purchase access or telemetry permissions.")
            }
        }
        .navigationTitle("Access duration")
    }
}
