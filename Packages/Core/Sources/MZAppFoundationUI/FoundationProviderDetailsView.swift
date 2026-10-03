import MZAppFoundation
import SwiftUI

struct FoundationProviderDetailsView: View {
    let services: AppServices
    let provider: FoundationProvider
    var body: some View {
        if services.developerOptions.isEnabled,
           let snapshot = services.providerSnapshots.first(where: { $0.provider == provider }) {
            List {
                Section {
                    DiagnosticValueRow("App expectation", value: snapshot.expectation.rawValue)
                    DiagnosticValueRow("Configuration", value: snapshot.configuration.rawValue)
                    DiagnosticValueRow("Runtime", value: snapshot.runtime.rawValue)
                    DiagnosticValueRow("Remote delivery", value: snapshot.delivery.rawValue)
                    DiagnosticValueRow("SDK version", value: snapshot.sdkVersion ?? "Not linked to this composition")
                    if let source = snapshot.versionSource { DiagnosticValueRow("Version source", value: source) }
                    #if os(macOS)
                    Text(snapshot.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    #endif
                } header: {
                    Text("Status")
                } footer: {
                    #if !os(macOS)
                    Text(snapshot.explanation).fixedSize(horizontal: false, vertical: true)
                    #endif
                }
                if !snapshot.findings.isEmpty {
                    Section("Findings") { ForEach(snapshot.findings) { FoundationFindingView(finding: $0) } }
                }
                Section("Identity and ownership") {
                    DiagnosticValueRow("Initialization owner", value: snapshot.identityAudit.ownership.rawValue)
                    identity("Expected by app", snapshot.identityAudit.expected)
                    identity("Supplied configuration", snapshot.identityAudit.supplied)
                    identity("Running SDK", snapshot.identityAudit.running)
                }
                if !snapshot.details.isEmpty {
                    Section("Configuration details") {
                        ForEach(snapshot.details) { detail in
                            DiagnosticValueRow(detail.label, value: detail.value)
                                .accessibilityIdentifier("mz.foundation.detail." + detail.id)
                        }
                    }
                }
                if provider == .revenueCat, let purchases = services.foundationDiagnostics.purchaseDiagnostics?() {
                    FoundationPurchaseDetailsView(snapshot: purchases)
                }
                FoundationVerificationActionsView(services: services, provider: provider)
            }
            .navigationTitle(provider.name)
            .accessibilityIdentifier("mz.foundation.details." + provider.rawValue)
        }
    }

    @ViewBuilder private func identity(_ label: String, _ identity: ProviderProjectIdentity?) -> some View {
        if let identity {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.headline)
                ForEach(identity.details) { DiagnosticValueRow($0.label, value: $0.value) }
            }
        } else { DiagnosticValueRow(label, value: "Unknown or not supplied") }
    }
}
