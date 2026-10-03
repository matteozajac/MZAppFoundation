import MZAppFoundation
import SwiftUI

public enum FoundationSettingsPresentation: Sendable { case automatic, sheet, window }

/// Add beside the app's primary WindowGroup on macOS and visionOS.
public struct FoundationSettingsScene: Scene {
    public static let id = "mzappfoundation.settings"
    private let services: AppServices
    private let pages: [FoundationDeveloperPage]

    public init(services: AppServices, pages: [FoundationDeveloperPage] = []) {
        self.services = services; self.pages = pages
    }

    public var body: some Scene {
        #if os(macOS)
        Window("App Foundation", id: Self.id) {
            FoundationSettingsView(services: services, pages: pages)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 960, height: 740)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        #else
        WindowGroup("App Foundation", id: Self.id) {
            FoundationSettingsView(services: services, pages: pages)
        }
        .defaultSize(width: 960, height: 740)
        #if os(visionOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
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
                Button("App Foundation") { openWindow(id: FoundationSettingsScene.id) }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Button("Developer Console") {
                    services.developerOptions.requestConsole()
                    openWindow(id: DeveloperOptions.consoleSceneID)
                }
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
    }
}
#endif
