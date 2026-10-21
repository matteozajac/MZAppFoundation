import Foundation

actor WorkerController {
    private var process: Process?
    private var log: FileHandle?

    struct State: Sendable {
        var isRunning: Bool
        var exitCode: Int32?
    }

    func start(configuration: InboxConfiguration) throws {
        guard process?.isRunning != true else { return }
        let worker = try workerURL()
        let interpreter = try pythonURL()
        try FileManager.default.createDirectory(
            at: InboxConfiguration.applicationSupport, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let logURL = InboxConfiguration.applicationSupport.appendingPathComponent("receiver.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw InboxError.message("Unable to create the receiver log.")
            }
        }
        try log?.close()
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        let task = makeProcess(interpreter: interpreter, worker: worker, arguments: ["watch"], log: handle)
        try task.run()
        log = handle
        process = task
    }

    func state() -> State {
        guard let process else { return State(isRunning: false) }
        return State(isRunning: process.isRunning, exitCode: process.isRunning ? nil : process.terminationStatus)
    }

    func retry(jobID: String) async throws {
        let task = try makeProcess(
            interpreter: pythonURL(), worker: workerURL(), arguments: ["retry", jobID], log: log
        )
        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { completed in continuation.resume(returning: completed.terminationStatus) }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
        guard exitCode == 0 else {
            throw InboxError.message("The report could not be retried. Open the receiver log for details.")
        }
    }

    /// SIGTERM stops new jobs; the worker finishes its current agent before exiting.
    func requestGracefulStop() {
        if process?.isRunning == true { process?.terminate() }
    }

    private func makeProcess(interpreter: URL, worker: URL, arguments: [String], log: FileHandle?) -> Process {
        let task = Process()
        task.executableURL = interpreter
        task.arguments = [worker.path, "--config", InboxConfiguration.configURL.path] + arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = log ?? FileHandle.nullDevice
        task.standardError = log ?? FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        let toolPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = toolPaths + ":" + (environment["PATH"] ?? "")
        task.environment = environment
        return task
    }

    private func workerURL() throws -> URL {
        guard let resources = Bundle.main.resourceURL else {
            throw InboxError.message("Install the packaged MZ Inbox app to use the receiver.")
        }
        let path = resources.appendingPathComponent("worker/inbox.py")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw InboxError.message("The receiver is missing from this app. Rebuild and install MZ Inbox.")
        }
        return path
    }

    private func pythonURL() throws -> URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "MZInboxPythonPath") as? String
        for path in [configured, "/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"].compactMap({ $0 }) {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        throw InboxError.message("Python 3 is required to receive reports. Install Python and rebuild MZ Inbox.")
    }
}
