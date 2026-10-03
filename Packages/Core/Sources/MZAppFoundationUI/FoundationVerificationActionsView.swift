import MZAppFoundation
import SwiftUI

struct FoundationVerificationActionsView: View {
    let services: AppServices
    let provider: FoundationProvider
    @State private var requestedID: String?
    @State private var results: [String: ProviderVerificationResult] = [:]

    var body: some View {
        let actions = services.foundationDiagnostics.actions.filter { $0.provider == provider }
        if !actions.isEmpty {
            Section {
                ForEach(actions) { action in
                    Button(action.title) { requestedID = action.id }
                        .disabled(requestedID != nil || !services.developerOptions.isEnabled)
                    if let result = results[action.id] {
                        DiagnosticValueRow(result.status.rawValue.capitalized, value: result.message)
                        Text(result.completedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if requestedID != nil { ProgressView("Checking provider…") }
            } header: { Text("Manual verification") } footer: {
                Text("These actions can contact the configured provider when runtime safety and delivery preferences permit it. Submitted events still need confirmation in the provider dashboard.")
            }
            .task(id: requestedID) {
                guard let requestedID, let action = actions.first(where: { $0.id == requestedID }),
                      services.developerOptions.isEnabled else { return }
                defer { self.requestedID = nil }
                services.telemetry.timeline.record(.verificationRequested, category: .verification, status: .updated, provider: provider)
                let result = await action.perform(context: services.providerInspectionContext)
                guard !Task.isCancelled, services.developerOptions.isEnabled else { return }
                results[action.id] = result
                let outcome: (DiagnosticTimelineEvent, DiagnosticTimelineStatus)
                switch result.status {
                case .submitted: outcome = (.verificationSubmitted, .submitted)
                case .confirmed: outcome = (.verificationConfirmed, .recorded)
                case .failed: outcome = (.verificationFailed, .failed)
                case .unavailable: outcome = (.verificationUnavailable, .blocked)
                }
                services.telemetry.timeline.record(outcome.0, category: .verification, status: outcome.1, provider: provider)
            }
        }
    }
}
