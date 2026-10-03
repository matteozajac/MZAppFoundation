import MZAppFoundation
import SwiftUI

#if os(macOS) || os(visionOS)
/// Included by `FoundationSettingsScene`, or register independently for app help.
public struct FoundationKeyboardShortcutsScene: Scene {
    public static let id = "mzappfoundation.keyboardShortcuts"
    private let options: DeveloperOptions
    private let sections: [FoundationKeyboardShortcutSection]

    public init(options: DeveloperOptions, sections: [FoundationKeyboardShortcutSection] = []) {
        self.options = options
        self.sections = sections
    }

    public var body: some Scene {
        #if os(macOS)
        Window("Keyboard Shortcuts", id: Self.id) {
            FoundationKeyboardShortcutsView(options: options, sections: sections)
                .frame(minWidth: 420, minHeight: 320)
        }
        .defaultSize(width: 540, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #else
        WindowGroup("Keyboard Shortcuts", id: Self.id) {
            NavigationStack { FoundationKeyboardShortcutsView(options: options, sections: sections) }
        }
        .defaultSize(width: 540, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}
#endif
