import MZAppFoundation
import SwiftUI

struct FoundationStartupView: View {
    let services: AppServices
    var body: some View {
        List {
            if services.foundationDiagnostics.startupRecords.isEmpty {
                Text("This composition did not supply startup records.").foregroundStyle(.secondary)
            }
            ForEach(services.foundationDiagnostics.startupRecords) { record in
                Section(record.provider?.name ?? "Composition") {
                    DiagnosticValueRow("Stage", value: record.stage.rawValue)
                    DiagnosticValueRow("Result", value: record.status.rawValue)
                    Text(record.message)
                    if let correction = record.correction { Text(correction).foregroundStyle(.secondary) }
                    DiagnosticValueRow("Recorded", value: record.recordedAt.formatted())
                }
            }
        }
        .navigationTitle("Startup history")
    }
}
