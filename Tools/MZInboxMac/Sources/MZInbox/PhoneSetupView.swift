import SwiftUI

@MainActor
struct PhoneSetupView: View {
    let model: InboxModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Send reports from your iPhone", systemImage: "iphone").font(.title2.bold())
            Text("Use the same Apple account for iCloud Drive on your phone and this Mac.")
            VStack(alignment: .leading, spacing: 14) {
                Text("1. On your iPhone, open Files → iCloud Drive → MZ Inbox → Send to my agent.shortcut and add it to Shortcuts.")
                Text("2. During setup, choose iCloud Drive → MZ Inbox → Incoming once. Future reports save there automatically.")
                Text("3. In any Foundation app, create a bug report, tap Share, and choose “Send to my agent”.")
            }
            if let shortcut = model.phoneShortcutPath {
                HStack {
                    Button("Show Shortcut File") { model.revealPath(shortcut) }
                }
                Text("You can also AirDrop this shortcut file to your iPhone and import it there. Choose the destination on the iPhone so its folder access belongs to that device.")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Mac incoming folder") {
                Text(model.configuration.inboxPath).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
            }
            HStack {
                Button("Open Incoming Folder", systemImage: "folder") { model.openPath(model.configuration.inboxPath) }
                Button("Copy Folder Path") { model.copy(model.configuration.inboxPath) }
            }
            Text("MZ Inbox processes each report once. The Mac must be awake; reports wait in iCloud until it is available. Your phone can read delivery status in MZ Inbox → Status in Files.")
                .foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(28)
        .frame(width: 610)
    }
}
