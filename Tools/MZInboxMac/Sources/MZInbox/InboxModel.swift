import AppKit
import Observation

@MainActor
@Observable
final class InboxModel {
    var configuration = InboxConfiguration.defaults
    var hasConfiguration = false
    var jobs: [InboxJob] = []
    var selectedJobID: String?
    var receiverIsRunning = false
    var receiverIssue: String?
    var alertMessage: String?
    var cloudDownloads = 0
    var lastScanAt: String?
    var retryingJobID: String?

    @ObservationIgnored private let files = InboxFileStore()
    @ObservationIgnored private let cloud = InboxCloudDownloader()
    @ObservationIgnored private let launcher = PathLauncher()
    @ObservationIgnored private let worker = WorkerController()
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var cloudMonitor: Task<Void, Never>?
    @ObservationIgnored private var receiverStartedAt: Date?
    @ObservationIgnored private var lastActiveAt: Date?

    var selectedJob: InboxJob? { jobs.first { $0.id == selectedJobID } }
    var activeJobs: Int { jobs.filter { ["inspecting", "transcribing", "investigating", "preparing", "preparing_fix", "running"].contains($0.status) }.count }
    var receiverTitle: String {
        if !hasConfiguration { return "Set up your inbox" }
        if configuration.paused { return activeJobs > 0 ? "Pausing after the current report" : "Processing paused" }
        if receiverIssue != nil { return "Receiver needs attention" }
        if cloudDownloads > 0 { return "Downloading reports from iCloud" }
        if activeJobs > 0 { return "Investigating a report" }
        return receiverIsRunning ? "Ready to receive reports" : "Receiver is stopped"
    }

    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            guard let self else { return }
            await loadConfiguration()
            if hasConfiguration { await startReceiver() }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(max(2, configuration.pollSeconds))) }
                catch { return }
            }
        }
        // One serial cloud task prevents overlapping scans. Its progress never
        // gates local controls or queue updates if File Provider stalls.
        cloudMonitor = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if hasConfiguration {
                    cloudDownloads = await cloud.requestDownloads(inboxPath: configuration.inboxPath)
                }
                do { try await Task.sleep(for: .seconds(max(2, configuration.pollSeconds))) }
                catch { return }
            }
        }
    }

    func loadConfiguration() async {
        do {
            let loaded = try await files.loadConfiguration()
            guard loaded.schemaVersion == 1 else {
                throw InboxError.message("Update MZ Inbox to read this configuration version.")
            }
            configuration = loaded
            hasConfiguration = true
        } catch {
            hasConfiguration = false
            receiverIssue = "Configure your inbox and app projects in Settings. \(error.localizedDescription)"
        }
    }

    func startReceiver() async {
        guard hasConfiguration else { return }
        do {
            try await worker.start(configuration: configuration)
            receiverIsRunning = true
            receiverStartedAt = .now
            receiverIssue = nil
        } catch { receiverIssue = error.localizedDescription }
    }

    func refresh() async {
        guard hasConfiguration else { return }
        do {
            configuration = try await files.loadConfiguration()
            let snapshot = try await files.snapshot(configuration: configuration)
            jobs = snapshot.jobs.sorted { ($0.receivedAt ?? "") > ($1.receivedAt ?? "") }
            lastScanAt = snapshot.lastScanAt
            let state = await worker.state()
            receiverIsRunning = state.isRunning
            if state.isRunning {
                let now = Date.now
                if activeJobs > 0 { lastActiveAt = now }
                receiverIssue = snapshot.workerError ?? delayedHeartbeatMessage(now: now)
            }
            if let code = state.exitCode {
                receiverIssue = snapshot.workerError ?? (code == 0
                    ? "The receiver stopped. Another MZ Inbox worker may already be running."
                    : "The receiver exited (\(code)). Open the receiver log for details, then restart it.")
            }
        } catch { receiverIssue = "Unable to read the inbox: \(error.localizedDescription)" }
    }

    private func delayedHeartbeatMessage(now: Date) -> String? {
        guard activeJobs == 0 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let heartbeat = lastScanAt.flatMap { fractional.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        // Give a fresh launch and a just-finished agent the same grace period as
        // a completed scan; a normal investigation can legitimately take minutes.
        let reference = [heartbeat, receiverStartedAt, lastActiveAt].compactMap { $0 }.max()
        guard let reference, now.timeIntervalSince(reference) > 90 else { return nil }
        return "iCloud report checking is delayed. Check iCloud Drive and the receiver log. Local pause controls and Settings remain available."
    }

    func saveConfiguration(_ updated: InboxConfiguration, expectedRoutes: [AppRoute]? = nil) async throws {
        guard !receiverIsRunning || updated.statePath == configuration.statePath else {
            throw InboxError.message("The private state folder cannot change while the receiver is running. Quit MZ Inbox before changing its configuration.")
        }
        let identifiers = updated.routes.map(\.bundleIdentifier)
        guard Set(identifiers).count == identifiers.count else {
            throw InboxError.message("Each app can have only one project route.")
        }
        for route in updated.routes {
            guard !route.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InboxError.message("Enter the app’s bundle identifier.")
            }
            guard await files.directoryExists(route.repository) else {
                throw InboxError.message("The project folder for \(route.name) does not exist.")
            }
        }
        try await files.saveConfiguration(updated, expectedRoutes: expectedRoutes)
        configuration = updated
        hasConfiguration = true
        if !receiverIsRunning { await startReceiver() }
        await refresh()
    }

    func togglePause() async {
        let expectedRoutes = configuration.routes
        var updated = configuration
        updated.paused.toggle()
        do { try await saveConfiguration(updated, expectedRoutes: expectedRoutes) }
        catch { alertMessage = error.localizedDescription }
    }

    func saveRoute(_ route: AppRoute, replacing identifier: String? = nil) async throws {
        let expectedRoutes = configuration.routes
        var updated = configuration
        if let identifier { updated.routes.removeAll { $0.bundleIdentifier == identifier } }
        guard !updated.routes.contains(where: { $0.bundleIdentifier == route.bundleIdentifier }) else {
            throw InboxError.message("This app already has a project. Edit its existing route in Settings.")
        }
        updated.routes.append(route)
        try await saveConfiguration(updated, expectedRoutes: expectedRoutes)
    }

    func retry(_ job: InboxJob) async {
        guard retryingJobID == nil else { return }
        retryingJobID = job.id
        defer { retryingJobID = nil }
        do {
            try await worker.retry(jobID: job.id)
            await refresh()
        } catch { alertMessage = error.localizedDescription }
    }

    func chooseFolder(startingAt path: String, prompt: String = "Choose") async -> String? {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.canCreateDirectories = true
        picker.prompt = prompt
        if !path.isEmpty { picker.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        guard await picker.begin() == .OK else { return nil }
        return picker.url?.path
    }

    func chooseFile(startingAt path: String, prompt: String = "Choose") async -> String? {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.prompt = prompt
        if !path.isEmpty { picker.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent() }
        guard await picker.begin() == .OK else { return nil }
        return picker.url?.path
    }

    func openPath(_ path: String) { launchPath(path) }
    func revealPath(_ path: String) { launchPath(path, reveal: true) }

    private func launchPath(_ path: String, reveal: Bool = false) {
        Task {
            do { try await launcher.open(path, reveal: reveal) }
            catch is CancellationError { }
            catch { alertMessage = error.localizedDescription }
        }
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var phoneShortcutPath: String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let shortcut = resources.appendingPathComponent("Send to my agent.shortcut")
        return FileManager.default.fileExists(atPath: shortcut.path) ? shortcut.path : nil
    }

    func shutdown() async {
        monitor?.cancel()
        monitor = nil
        cloudMonitor?.cancel()
        cloudMonitor = nil
        await launcher.shutdown()
        await worker.requestGracefulStop()
    }
}
