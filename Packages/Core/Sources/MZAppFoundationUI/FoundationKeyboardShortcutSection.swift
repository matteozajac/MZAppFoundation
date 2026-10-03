/// App-owned shortcuts can share the foundation's help page without moving
/// feature actions or their availability rules into the package.
public struct FoundationKeyboardShortcutSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let shortcuts: [FoundationKeyboardShortcut]

    public init(id: String, title: String, detail: String? = nil, shortcuts: [FoundationKeyboardShortcut]) {
        self.id = id
        self.title = title
        self.detail = detail
        self.shortcuts = shortcuts
    }
}
