import MZAppFoundation
import SwiftUI

/// Drop into any settings List or Form. Owns its presentation and disappears when developer mode is off.
public struct FoundationSettingsLink: View {
    private let services: AppServices
    private let pages: [FoundationDeveloperPage]
    private let keyboardShortcutSections: [FoundationKeyboardShortcutSection]
    private let presentation: FoundationSettingsPresentation
    @State private var isPresented = false
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(services: AppServices, pages: [FoundationDeveloperPage] = [],
                keyboardShortcutSections: [FoundationKeyboardShortcutSection] = [],
                presentation: FoundationSettingsPresentation = .automatic) {
        self.services = services; self.pages = pages; self.presentation = presentation
        self.keyboardShortcutSections = keyboardShortcutSections
    }

    public var body: some View {
        Group {
            if services.developerOptions.isEnabled {
                Button {
                    #if os(macOS) || os(visionOS)
                    if presentation != .sheet { openWindow(id: FoundationSettingsScene.id) }
                    else { isPresented = true }
                    #else
                    isPresented = true
                    #endif
                } label: {
                    Label("App Foundation", systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("mz.foundation.settings.link")
            }
        }
        .sheet(isPresented: $isPresented) {
            FoundationSettingsView(services: services, pages: pages, keyboardShortcutSections: keyboardShortcutSections)
        }
        .onChange(of: services.developerOptions.isEnabled) { _, enabled in
            if !enabled { isPresented = false }
        }
    }
}
