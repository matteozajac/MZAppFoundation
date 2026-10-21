import AppKit
import SwiftUI

@main
@MainActor
struct MZInboxApp: App {
    @NSApplicationDelegateAdaptor(InboxAppDelegate.self) private var delegate
    @State private var model: InboxModel
    private let menuBarIcon: NSImage

    init() {
        let model = InboxModel()
        _model = State(initialValue: model)
        InboxAppDelegate.model = model
        let image = Bundle.main.url(forResource: "RabbitTemplate", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "hare.fill", accessibilityDescription: "MZ Inbox")
            ?? NSImage()
        image.size = NSSize(width: 15, height: 18)
        image.isTemplate = true
        menuBarIcon = image
    }

    var body: some Scene {
        Window("MZ Inbox", id: "inbox") {
            InboxView(model: model)
        }
        .defaultSize(width: 900, height: 600)

        MenuBarExtra {
            InboxMenu(model: model)
        } label: {
            Label {
                Text(model.configuration.paused ? "MZ Inbox — Processing paused" : "MZ Inbox")
            } icon: {
                HStack(spacing: 2) {
                    Image(nsImage: menuBarIcon)
                    if model.configuration.paused {
                        Image(systemName: "pause.fill")
                    }
                }
            }
        }

        Settings {
            InboxSettingsView(model: model)
        }
    }
}

@MainActor
final class InboxAppDelegate: NSObject, NSApplicationDelegate {
    static var model: InboxModel?
    private var quitRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        Self.model?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitRequested else { return .terminateNow }
        quitRequested = true
        Task {
            await Self.model?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
