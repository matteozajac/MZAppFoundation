import SwiftUI

struct FoundationKeyboardShortcutRow: View {
    let shortcut: FoundationKeyboardShortcut
    let isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shortcut.title)
                    Spacer(minLength: 16)
                    Text(shortcut.display).monospaced().foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcut.title)
                    Text(shortcut.display).monospaced().foregroundStyle(.secondary)
                }
            }
            if let detail = shortcut.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if !isAvailable {
                Label("Enable developer mode to use this shortcut.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.title)
        .accessibilityValue(shortcut.accessibilityDescription)
        .accessibilityHint([shortcut.detail, isAvailable ? nil : "Unavailable while developer mode is off."].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("mz.foundation.shortcut." + shortcut.id)
    }
}
