import MZAppFoundation
import SwiftUI

/// Drop into any settings List or Form. On macOS/visionOS, automatic presentation
/// uses the help window registered by `FoundationSettingsScene` or `FoundationKeyboardShortcutsScene`.
public struct FoundationKeyboardShortcutsLink: View {
    private let options: DeveloperOptions
    private let sections: [FoundationKeyboardShortcutSection]
    private let presentation: FoundationSettingsPresentation
    @State private var isPresented = false
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(options: DeveloperOptions, sections: [FoundationKeyboardShortcutSection] = [],
                presentation: FoundationSettingsPresentation = .automatic) {
        self.options = options
        self.sections = sections
        self.presentation = presentation
    }

    public var body: some View {
        Button("Keyboard Shortcuts", systemImage: "keyboard", action: openHelp)
            .accessibilityIdentifier("mz.foundation.shortcuts.link")
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    FoundationKeyboardShortcutsView(options: options, sections: sections)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isPresented = false }
                            }
                        }
                }
            }
    }

    private func openHelp() {
        #if os(macOS) || os(visionOS)
        if presentation != .sheet { openWindow(id: FoundationKeyboardShortcutsScene.id) }
        else { isPresented = true }
        #else
        isPresented = true
        #endif
    }
}
