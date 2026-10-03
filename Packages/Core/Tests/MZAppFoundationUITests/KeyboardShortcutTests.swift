import SwiftUI
import Testing
@testable import MZAppFoundationUI

struct KeyboardShortcutTests {
    @Test func appSectionsCannotReplaceProtectedBindingsOrDuplicateRowIdentity() throws {
        let appShortcut = FoundationKeyboardShortcut(id: "reader.next", title: "Next chapter", key: .rightArrow, modifiers: [])
        let attemptedOverride = FoundationKeyboardShortcut(id: FoundationKeyboardShortcutCatalog.developerConsole.id,
            title: "Unprotected console", key: "x")
        let sections = FoundationKeyboardShortcutCatalog.sections(appSections: [
            .init(id: "reader", title: "Reading", shortcuts: [attemptedOverride, appShortcut, appShortcut]),
            .init(id: "reader", title: "Duplicate section", shortcuts: [.init(id: "other", title: "Other", key: "o")]),
            .init(id: "empty", title: "Empty", shortcuts: []),
            .init(id: "duplicates", title: "Duplicate rows", shortcuts: [appShortcut])
        ])
        #expect(sections.map(\.id) == [FoundationKeyboardShortcutCatalog.developerSection.id, "reader"])
        let console = try #require(sections.first?.shortcuts.first)
        #expect(console.requiresDeveloperMode)
        #expect(console.key == "d" && console.modifiers == .command)
        #expect(sections.last?.shortcuts == [appShortcut])
    }

    @Test func helpDescribesSpecialKeysAndModifierOrderWithoutChangingTheBinding() {
        let next = FoundationKeyboardShortcut(id: "reader.next", title: "Next chapter", key: .rightArrow, modifiers: [])
        #expect(next.display == "→")
        #expect(next.accessibilityDescription == "Right Arrow")
        #expect(next.shortcut == KeyboardShortcut(.rightArrow, modifiers: []))
        let playback = FoundationKeyboardShortcut(id: "player.play", title: "Play or pause", key: .space,
            modifiers: [.command, .shift, .option, .control], aliases: [KeyboardShortcut(.return, modifiers: [])])
        #expect(playback.display == "⌃⌥⇧⌘Space or Return")
        #expect(playback.accessibilityDescription == "Control + Option + Shift + Command + Space or Return")
    }
}
