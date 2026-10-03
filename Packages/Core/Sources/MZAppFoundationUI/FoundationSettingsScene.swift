import MZAppFoundation
import SwiftUI

public enum FoundationSettingsPresentation: Sendable { case automatic, sheet, window }

/// Add beside the app's primary WindowGroup on macOS and visionOS.
public struct FoundationSettingsScene: Scene {
    public static let id = "mzappfoundation.settings"
    private let services: AppServices
    private let pages: [FoundationDeveloperPage]
    private let keyboardShortcutSections: [FoundationKeyboardShortcutSection]

    public init(services: AppServices, pages: [FoundationDeveloperPage] = [],
                keyboardShortcutSections: [FoundationKeyboardShortcutSection] = []) {
        self.services = services; self.pages = pages
        self.keyboardShortcutSections = keyboardShortcutSections
    }

    public var body: some Scene {
        #if os(macOS)
        Window("App Foundation", id: Self.id) {
            FoundationSettingsView(services: services, pages: pages, keyboardShortcutSections: keyboardShortcutSections)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 960, height: 740)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        #else
        WindowGroup("App Foundation", id: Self.id) {
            FoundationSettingsView(services: services, pages: pages, keyboardShortcutSections: keyboardShortcutSections)
        }
        .defaultSize(width: 960, height: 740)
        #if os(visionOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
        #endif
        #if os(macOS) || os(visionOS)
        FoundationKeyboardShortcutsScene(options: services.developerOptions, sections: keyboardShortcutSections)
        #endif
    }
}

#if os(macOS)
public struct FoundationSettingsCommands: Commands {
    private let services: AppServices
    @Environment(\.openWindow) private var openWindow

    public init(services: AppServices) { self.services = services }

    public var body: some Commands {
        CommandMenu("Developer") {
            if services.developerOptions.isEnabled {
                Button("App Foundation", action: openSettings)
                    .keyboardShortcut(FoundationKeyboardShortcutCatalog.developerSettings.shortcut)
                Button("Developer Console") {
                    openConsole()
                }
                    .keyboardShortcut(FoundationKeyboardShortcutCatalog.developerConsole.shortcut)
                Button("Developer Console (Alternate)", action: openConsole)
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: FoundationKeyboardShortcutsScene.id) }
        }
    }

    private func openConsole() {
        services.developerOptions.refreshExpiration()
        guard services.developerOptions.isEnabled else { return }
        services.developerOptions.requestConsole()
        openWindow(id: DeveloperOptions.consoleSceneID)
    }

    private func openSettings() {
        services.developerOptions.refreshExpiration()
        guard services.developerOptions.isEnabled else { return }
        openWindow(id: FoundationSettingsScene.id)
    }
}
#endif
