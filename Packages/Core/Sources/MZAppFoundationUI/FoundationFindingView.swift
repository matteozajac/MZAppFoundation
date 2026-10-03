import MZAppFoundation
import SwiftUI

struct FoundationFindingView: View {
    let finding: DiagnosticFinding
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(finding.message, systemImage: finding.severity == .info ? "info.circle" : "exclamationmark.triangle")
            if let correction = finding.correction { Text(correction).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FoundationAppServiceView: View {
    let section: FoundationDiagnosticSection
    var body: some View {
        List {
            Section { Text(section.summary) }
            if !section.findings.isEmpty {
                Section("Findings") { ForEach(section.findings) { FoundationFindingView(finding: $0) } }
            }
            Section("Details") { ForEach(section.details) { DiagnosticValueRow($0.label, value: $0.value) } }
        }
        .navigationTitle(section.title)
    }
}
