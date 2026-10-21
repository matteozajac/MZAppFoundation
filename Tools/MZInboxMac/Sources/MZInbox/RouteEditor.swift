import SwiftUI

struct RouteEditRequest: Identifiable {
    let id = UUID()
    var route: AppRoute
    var originalIdentifier: String?
}

@MainActor
struct RouteEditor: View {
    let model: InboxModel
    let save: @MainActor (AppRoute) async throws -> Void
    @State private var route: AppRoute
    @State private var errorMessage: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(model: InboxModel, route: AppRoute, save: @escaping @MainActor (AppRoute) async throws -> Void) {
        self.model = model
        self.save = save
        _route = State(initialValue: route)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect an app to its project").font(.title2.bold())
            Text("New reports from this app will start the selected agent workflow on this Mac.")
                .foregroundStyle(.secondary)
            Form {
                TextField("App name", text: $route.name)
                TextField("Bundle identifier", text: $route.bundleIdentifier)
                    .help("Use the app’s bundle identifier, such as com.example.MyApp.")
                LabeledContent("Project folder") {
                    HStack {
                        Text(route.repository.isEmpty ? "Choose a local Git repository" : route.repository)
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                            .foregroundStyle(route.repository.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") {
                            Task {
                                if let path = await model.chooseFolder(startingAt: route.repository, prompt: "Select Project") {
                                    route.repository = path
                                }
                            }
                        }
                    }
                }
                Picker("When a report arrives", selection: $route.mode) {
                    ForEach(AppRoute.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Text(route.mode.explanation).foregroundStyle(.secondary)
                Toggle("Process reports from this app", isOn: $route.enabled)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save Project") {
                    Task { await saveRoute() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || route.repository.isEmpty || route.bundleIdentifier.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    private func saveRoute() async {
        isSaving = true
        defer { isSaving = false }
        var cleaned = route
        cleaned.bundleIdentifier = route.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.name = route.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = cleaned.bundleIdentifier }
        do {
            try await save(cleaned)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
