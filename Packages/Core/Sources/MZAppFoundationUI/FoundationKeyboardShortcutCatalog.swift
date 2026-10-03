import SwiftUI

/// Bindings installed by `appDeveloperTools` and `FoundationSettingsCommands`.
public enum FoundationKeyboardShortcutCatalog {
    public static let developerConsole = FoundationKeyboardShortcut(
        id: "mz.developer.console", title: "Developer Console", key: "d",
        aliases: consoleAliases, detail: "Open local logs and available bug reporting tools.", requiresDeveloperMode: true)

    #if os(macOS)
    /// Includes Control to avoid macOS's Option–Command–D shortcut for the Dock.
    public static let developerSettings = FoundationKeyboardShortcut(
        id: "mz.foundation.settings", title: "App Foundation", key: "d", modifiers: [.control, .option, .command],
        detail: "Open provider diagnostics and developer tools.", requiresDeveloperMode: true)
    #endif

    public static let developerSection = FoundationKeyboardShortcutSection(
        id: "mz.foundation.developer", title: "Developer tools",
        detail: "Developer shortcuts require developer mode. They do not enable it.", shortcuts: developerShortcuts)

    /// Foundation rows take precedence when an injected identifier is repeated.
    /// Empty sections and duplicate identifiers are removed before SwiftUI renders them.
    public static func sections(appSections: [FoundationKeyboardShortcutSection] = []) -> [FoundationKeyboardShortcutSection] {
        var sectionIDs = Set<String>()
        var shortcutIDs = Set<String>()
        return ([developerSection] + appSections).compactMap { section in
            guard sectionIDs.insert(section.id).inserted else { return nil }
            let shortcuts = section.shortcuts.filter { shortcutIDs.insert($0.id).inserted }
            guard !shortcuts.isEmpty else { return nil }
            return FoundationKeyboardShortcutSection(id: section.id, title: section.title, detail: section.detail, shortcuts: shortcuts)
        }
    }

    private static var consoleAliases: [KeyboardShortcut] {
        #if os(macOS)
        [KeyboardShortcut("l", modifiers: [.command, .option])]
        #else
        []
        #endif
    }

    private static var developerShortcuts: [FoundationKeyboardShortcut] {
        #if os(macOS)
        [developerConsole, developerSettings]
        #else
        [developerConsole]
        #endif
    }
}
