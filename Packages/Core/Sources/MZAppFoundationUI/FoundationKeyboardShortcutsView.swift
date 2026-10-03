import MZAppFoundation
import SwiftUI

/// Shared help content for app settings, reader help, or a developer destination.
/// It remains readable while developer mode is off and marks protected shortcuts inactive.
public struct FoundationKeyboardShortcutsView: View {
    private let options: DeveloperOptions
    private let sections: [FoundationKeyboardShortcutSection]
    @Environment(\.scenePhase) private var scenePhase

    public init(options: DeveloperOptions, sections: [FoundationKeyboardShortcutSection] = []) {
        self.options = options
        self.sections = FoundationKeyboardShortcutCatalog.sections(appSections: sections)
    }

    public var body: some View {
        List {
            Section {
                Text("Use these shortcuts with a connected keyboard while the app is active.")
                #if os(iOS) || os(visionOS)
                Text("Hold Command to see the shortcuts available on the current screen.")
                    .foregroundStyle(.secondary)
                #endif
                if !options.isEnabled {
                    Label("Developer mode is off", systemImage: "lock")
                        .accessibilityIdentifier("mz.foundation.shortcuts.developerDisabled")
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.shortcuts) { shortcut in
                        FoundationKeyboardShortcutRow(shortcut: shortcut,
                            isAvailable: !shortcut.requiresDeveloperMode || options.isEnabled)
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if let detail = section.detail { Text(detail) }
                }
            }
        }
        .navigationTitle("Keyboard Shortcuts")
        .accessibilityIdentifier("mz.foundation.shortcuts")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { options.refreshExpiration() }
        }
    }
}
