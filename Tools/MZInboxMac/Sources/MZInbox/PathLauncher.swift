import Foundation

/// Launch Services can block while issuing an iCloud sandbox extension. Run its
/// command-line client in a bounded child process rather than on the UI thread.
actor PathLauncher {
    private struct Request {
        let process: Process
        let continuation: CheckedContinuation<Void, any Error>
        var timeout: Task<Void, Never>?
    }

    private var requests: [UUID: Request] = [:]

    func open(_ path: String, reveal: Bool = false) async throws {
        guard path.hasPrefix("/") else {
            throw InboxError.message("The item needs an absolute local path before it can be opened.")
        }
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = reveal ? ["-R", path] : [path]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                process.terminationHandler = { [weak self] completed in
                    let code = completed.terminationStatus
                    Task { await self?.finish(id, exitCode: code) }
                }
                requests[id] = Request(process: process, continuation: continuation)
                do {
                    try process.run()
                    requests[id]?.timeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(8)) }
                        catch { return }
                        await self?.timeout(id)
                    }
                } catch {
                    requests.removeValue(forKey: id)?.continuation.resume(
                        throwing: InboxError.message("The item could not be opened. Try again from Finder.")
                    )
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func shutdown() {
        for id in Array(requests.keys) { cancel(id) }
    }

    private func finish(_ id: UUID, exitCode: Int32) {
        guard let request = requests.removeValue(forKey: id) else { return }
        request.timeout?.cancel()
        if exitCode == 0 { request.continuation.resume() }
        else {
            request.continuation.resume(
                throwing: InboxError.message("The item could not be opened. Check that it exists and try again from Finder.")
            )
        }
    }

    private func timeout(_ id: UUID) {
        guard let request = requests.removeValue(forKey: id) else { return }
        request.process.terminationHandler = nil
        if request.process.isRunning { request.process.terminate() }
        request.continuation.resume(
            throwing: InboxError.message("Opening this item is taking too long. Check iCloud Drive and try again from Finder. MZ Inbox is still running.")
        )
    }

    private func cancel(_ id: UUID) {
        guard let request = requests.removeValue(forKey: id) else { return }
        request.timeout?.cancel()
        request.process.terminationHandler = nil
        if request.process.isRunning { request.process.terminate() }
        request.continuation.resume(throwing: CancellationError())
    }
}
