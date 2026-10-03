#if os(macOS)
import CoreData
import Pulse
import SwiftUI

/// Pulse's public ConsoleView is unavailable on macOS. Show its local technical log store natively.
struct FoundationMacConsole: View {
    var body: some View {
        FoundationMacLogList().environment(\.managedObjectContext, LoggerStore.shared.viewContext)
    }
}

private struct FoundationMacLogList: View {
    @FetchRequest private var messages: FetchedResults<LoggerMessageEntity>
    @State private var query = ""

    init() {
        let request = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LoggerMessageEntity.createdAt, ascending: false)]
        request.predicate = NSPredicate(format: "task == nil")
        request.fetchLimit = 500
        _messages = FetchRequest(fetchRequest: request)
    }

    var body: some View {
        List {
            Section {
                Text("The latest 500 local log messages. Network bodies and metadata are excluded from this view.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(messages.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query) }) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text).textSelection(.enabled)
                    Text(message.label + " · " + message.createdAt.formatted(date: .omitted, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message.text + ", " + message.label + " · " + message.createdAt.formatted(date: .omitted, time: .standard))
            }
        }
        .searchable(text: $query, prompt: "Search local logs")
        .navigationTitle("Developer Console")
    }
}
#endif
