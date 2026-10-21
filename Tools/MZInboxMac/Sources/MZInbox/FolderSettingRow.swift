import SwiftUI

@MainActor
struct FolderSettingRow: View {
    let model: InboxModel
    let title: String
    @Binding var path: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("Choose…") {
                    Task {
                        if let selected = await model.chooseFolder(startingAt: path) { path = selected }
                    }
                }
                .accessibilityLabel("Choose \(title.lowercased())")
            }
        }
    }
}
