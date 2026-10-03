import SwiftUI

/// A discoverable shortcut. Apps install their own actions and can reuse `shortcut`
/// with SwiftUI's `keyboardShortcut(_:)` to keep bindings and help in sync.
public struct FoundationKeyboardShortcut: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let shortcut: KeyboardShortcut
    public let aliases: [KeyboardShortcut]
    public let detail: String?
    public let requiresDeveloperMode: Bool

    public init(id: String, title: String, key: KeyEquivalent, modifiers: EventModifiers = .command,
                aliases: [KeyboardShortcut] = [], detail: String? = nil, requiresDeveloperMode: Bool = false) {
        self.id = id
        self.title = title
        self.shortcut = KeyboardShortcut(key, modifiers: modifiers)
        self.aliases = aliases
        self.detail = detail
        self.requiresDeveloperMode = requiresDeveloperMode
    }

    public var key: KeyEquivalent { shortcut.key }
    public var modifiers: EventModifiers { shortcut.modifiers }

    /// Readable key equivalents, including arrows and the space/return keys.
    public var display: String {
        ([shortcut] + aliases).map(Self.display).joined(separator: " or ")
    }

    public var accessibilityDescription: String {
        ([shortcut] + aliases).map(Self.accessibilityDescription).joined(separator: " or ")
    }

    private static func display(_ shortcut: KeyboardShortcut) -> String {
        var symbols = ""
        if shortcut.modifiers.contains(.control) { symbols += "⌃" }
        if shortcut.modifiers.contains(.option) { symbols += "⌥" }
        if shortcut.modifiers.contains(.shift) { symbols += "⇧" }
        if shortcut.modifiers.contains(.command) { symbols += "⌘" }
        if shortcut.modifiers.contains(.capsLock) { symbols += "⇪" }
        return symbols + keyLabel(shortcut.key, accessible: false)
    }

    private static func accessibilityDescription(_ shortcut: KeyboardShortcut) -> String {
        var names: [String] = []
        if shortcut.modifiers.contains(.control) { names.append("Control") }
        if shortcut.modifiers.contains(.option) { names.append("Option") }
        if shortcut.modifiers.contains(.shift) { names.append("Shift") }
        if shortcut.modifiers.contains(.command) { names.append("Command") }
        if shortcut.modifiers.contains(.capsLock) { names.append("Caps Lock") }
        names.append(keyLabel(shortcut.key, accessible: true))
        return names.joined(separator: " + ")
    }

    private static func keyLabel(_ key: KeyEquivalent, accessible: Bool) -> String {
        switch key {
        case .upArrow: accessible ? "Up Arrow" : "↑"
        case .downArrow: accessible ? "Down Arrow" : "↓"
        case .leftArrow: accessible ? "Left Arrow" : "←"
        case .rightArrow: accessible ? "Right Arrow" : "→"
        case .escape: accessible ? "Escape" : "Esc"
        case .delete: accessible ? "Delete" : "⌫"
        case .deleteForward: accessible ? "Forward Delete" : "⌦"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .clear: "Clear"
        case .tab: "Tab"
        case .space: "Space"
        case .return: "Return"
        default: String(key.character).uppercased()
        }
    }
}
