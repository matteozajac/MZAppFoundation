import MZAppFoundation
import SwiftUI

struct FoundationTimelineView: View {
    let services: AppServices
    var body: some View {
        List {
            Section {
                Text("Current process only. This bounded timeline contains event types and outcomes, without event payloads.")
                DiagnosticValueRow("Capacity", value: String(services.telemetry.timeline.capacity))
                DiagnosticValueRow("Older entries discarded", value: String(services.telemetry.timeline.discardedEntries))
                Button("Clear timeline", role: .destructive) { services.telemetry.timeline.clear() }
            }
            ForEach(services.telemetry.timeline.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.event.rawValue).font(.headline)
                    Text([entry.category.rawValue, entry.status.rawValue, entry.provider?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(entry.timestamp.formatted(date: .omitted, time: .standard)).font(.caption)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Session timeline")
    }
}
