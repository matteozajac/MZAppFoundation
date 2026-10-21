import AppKit
import SwiftUI

@MainActor
struct InboxMenu: View {
    let model: InboxModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.receiverTitle)
        if model.activeJobs > 0 { Text("\(model.activeJobs) active report(s)") }
        Divider()
        Button("Open MZ Inbox", systemImage: "tray.full") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "inbox")
        }
        Button(model.configuration.paused ? "Resume Processing" : "Pause Processing",
               systemImage: model.configuration.paused ? "play" : "pause") {
            Task { await model.togglePause() }
        }
        .disabled(!model.hasConfiguration)
        Button("Open Incoming Folder", systemImage: "folder") { model.openPath(model.configuration.inboxPath) }
        Button("Open Phone Status Folder", systemImage: "icloud") { model.openPath(model.configuration.statusPath) }
        Divider()
        Button("Settings…", systemImage: "gearshape") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Quit MZ Inbox") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    }
}
