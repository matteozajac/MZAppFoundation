import SwiftUI

struct DiagnosticValueRow: View {
    let label: String
    let value: String
    init(_ label: String, value: String) { self.label = label; self.value = value }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
        .padding(.vertical, 2)
        #if os(macOS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ": " + value)
        #else
        .accessibilityElement(children: .combine)
        #endif
    }
}
