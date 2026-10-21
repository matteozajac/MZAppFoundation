import SwiftUI

@MainActor
struct InboxSettingsView: View {
    let model: InboxModel
    @State private var draft = InboxConfiguration.defaults
    @State private var baselineRoutes: [AppRoute] = []
    @State private var whisperPath = ""
    @State private var routeRequest: RouteEditRequest?
    @State private var isSaving = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(draft.routes) { route in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).font(.headline)
                                Text(route.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                                Text(route.repository).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Text(route.enabled ? route.mode.title : "Processing disabled")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { routeRequest = RouteEditRequest(route: route, originalIdentifier: route.bundleIdentifier) }
                            Button("Remove", role: .destructive) { draft.routes.removeAll { $0.id == route.id } }
                        }
                        .padding(.vertical, 4)
                    }
                    Button("Add App Project", systemImage: "plus") {
                        routeRequest = RouteEditRequest(route: AppRoute(bundleIdentifier: "", name: "", repository: ""))
                    }
                } header: { Text("App projects") } footer: {
                    Text("Investigate saves findings. Prepare a fix uses an isolated Git worktree. Save Settings to apply your project changes.")
                }
                Section("Delivery folders") {
                    FolderSettingRow(model: model, title: "Incoming reports", path: $draft.inboxPath)
                    FolderSettingRow(model: model, title: "Phone status", path: $draft.statusPath)
                    LabeledContent("Private Mac state") {
                        HStack {
                            Text(draft.statePath).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                            Spacer()
                            Button("Show in Finder") { model.revealPath(draft.statePath) }
                        }
                    }
                    Text("Incoming reports and phone status should be in iCloud Drive. Evidence, agent results, and project paths stay in the private Mac state folder.")
                        .foregroundStyle(.secondary)
                }
                Section("Agent and voice notes") {
                    HStack {
                        TextField("Codex executable", text: $draft.codexPath)
                        Button("Choose…") {
                            Task {
                                if let path = await model.chooseFile(startingAt: draft.codexPath) { draft.codexPath = path }
                            }
                        }
                        .accessibilityLabel("Choose Codex executable")
                    }
                    HStack {
                        TextField("Whisper model (optional)", text: $whisperPath)
                        Button("Choose…") {
                            Task {
                                if let path = await model.chooseFile(startingAt: whisperPath) { whisperPath = path }
                            }
                        }
                        .accessibilityLabel("Choose Whisper model")
                    }
                    Stepper("Check for reports every \(draft.pollSeconds) seconds", value: $draft.pollSeconds, in: 2...60)
                    Text("Codex uses your existing local sign-in. Voice notes are transcribed on this Mac when a Whisper model is configured.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let message {
                    Label(message, systemImage: messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(messageIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Reload") { loadDraft() }.disabled(isSaving)
                Button(isSaving ? "Saving…" : "Save Settings") { Task { await save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
            .padding(18)
        }
        .frame(width: 760, height: 680)
        .onAppear { loadDraft() }
        .sheet(item: $routeRequest) { request in
            RouteEditor(model: model, route: request.route) { route in
                var updated = draft.routes
                if let original = request.originalIdentifier { updated.removeAll { $0.bundleIdentifier == original } }
                guard !updated.contains(where: { $0.bundleIdentifier == route.bundleIdentifier }) else {
                    throw InboxError.message("This app already has a project route.")
                }
                updated.append(route)
                draft.routes = updated
                message = "Project changes are ready to save."
                messageIsError = false
            }
        }
    }

    private func loadDraft() {
        draft = model.configuration
        baselineRoutes = draft.routes
        whisperPath = draft.whisperModel ?? ""
        message = nil
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = draft
        let modelPath = whisperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.whisperModel = modelPath.isEmpty ? nil : modelPath
        updated.paused = model.configuration.paused
        do {
            try await model.saveConfiguration(updated, expectedRoutes: baselineRoutes)
            draft = model.configuration
            baselineRoutes = draft.routes
            message = "Settings saved."
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}
