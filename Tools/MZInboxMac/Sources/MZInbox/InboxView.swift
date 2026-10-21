import SwiftUI

@MainActor
struct InboxView: View {
    @Bindable var model: InboxModel
    @State private var showingPhoneSetup = false
    @State private var showingAlert = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedJobID) {
                ForEach(model.jobs) { job in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(job.title).font(.headline).lineLimit(2)
                        Text(job.appName).font(.subheadline).foregroundStyle(.secondary)
                        Label(job.statusTitle, systemImage: job.symbol).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .tag(job.id)
                }
            }
            .overlay {
                if model.jobs.isEmpty {
                    ContentUnavailableView("No reports yet", systemImage: "tray",
                                           description: Text("Reports sent from your phone will appear here."))
                }
            }
            .navigationTitle("Reports")
            .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } detail: {
            VStack(spacing: 0) {
                receiverBanner
                Divider()
                if let job = model.selectedJob {
                    JobDetailView(model: model, job: job)
                } else {
                    ContentUnavailableView("Send a report from your phone", systemImage: "iphone.and.arrow.right.outward",
                                           description: Text("Share a report ZIP with your shortcut. MZ Inbox downloads it and starts the agent for that app."))
                    Button("Phone Setup") { showingPhoneSetup = true }.padding(.bottom, 40)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .toolbar {
            Button("Open Incoming Folder", systemImage: "folder") { model.openPath(model.configuration.inboxPath) }
            Button("Phone Setup", systemImage: "iphone") { showingPhoneSetup = true }
            Button(model.configuration.paused ? "Resume Processing" : "Pause Processing",
                   systemImage: model.configuration.paused ? "play" : "pause") {
                Task { await model.togglePause() }
            }
            .disabled(!model.hasConfiguration)
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
            Button("Settings", systemImage: "gearshape") { openSettings() }
        }
        .sheet(isPresented: $showingPhoneSetup) { PhoneSetupView(model: model) }
        .onChange(of: model.alertMessage) { _, message in showingAlert = message != nil }
        .alert("MZ Inbox", isPresented: $showingAlert, presenting: model.alertMessage) { _ in
            Button("OK") { model.alertMessage = nil }
        } message: { message in Text(message) }
    }

    private var receiverBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.receiverTitle, systemImage: model.configuration.paused ? "pause.circle" : "tray.and.arrow.down")
                    .font(.headline)
                Spacer()
                if model.receiverIssue != nil && model.hasConfiguration && !model.receiverIsRunning {
                    Button("Start Receiver") { Task { await model.startReceiver() } }
                }
            }
            if let issue = model.receiverIssue {
                Text(issue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Open Settings") { openSettings() }
                    Button("Open Receiver Log") {
                        model.openPath(InboxConfiguration.applicationSupport.appendingPathComponent("receiver.log").path)
                    }
                }
            } else if model.configuration.paused {
                Text("Reports continue arriving. Resume when you want the agent to start new work.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
