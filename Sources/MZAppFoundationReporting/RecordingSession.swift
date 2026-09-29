#if os(iOS)
import Observation
@preconcurrency import ReplayKit

/// Isolates ReplayKit's legacy callback boundary from the recording lifecycle.
@MainActor protocol ScreenCaptureDriver: AnyObject {
    var isAvailable: Bool { get }
    var isRecording: Bool { get }
    func startCapture(handler: @escaping @Sendable (CMSampleBuffer, RPSampleBufferType, (any Error)?) -> Void) async throws
    func stopCapture() async
}

@MainActor final class ReplayKitCaptureDriver: ScreenCaptureDriver {
    private var recorder: RPScreenRecorder { .shared() }
    var isAvailable: Bool { recorder.isAvailable }
    var isRecording: Bool { recorder.isRecording }

    func startCapture(handler: @escaping @Sendable (CMSampleBuffer, RPSampleBufferType, (any Error)?) -> Void) async throws {
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        try await recorder.startCapture(handler: handler)
    }

    func stopCapture() async {
        await withCheckedContinuation { continuation in
            // ReplayKit completes on an XPC queue. Inheriting MainActor here
            // traps before the continuation can resume (APPLE-IOS-5E).
            recorder.stopCapture { @Sendable _ in continuation.resume() }
        }
    }
}

@MainActor @Observable
final class RecordingSession {
    private(set) var status = BugReportStrings.text("bug_recording_off")
    private(set) var isRecording = false
    private var enabled = false
    private var active = false
    private var suspended = false
    private var failed = false
    private var ownsCapture = false
    private var worker: Task<Void, Never>?
    private var buffer: RollingVideoBuffer?
    private var directory: URL?
    private let files: ReportFiles
    private let recorder: any ScreenCaptureDriver

    init(files: ReportFiles, recorder: any ScreenCaptureDriver = ReplayKitCaptureDriver()) {
        self.files = files
        self.recorder = recorder
    }

    func waitUntilSettled() async { await worker?.value }

    func update(enabled: Bool, active: Bool) {
        if enabled && !self.enabled { failed = false }
        self.enabled = enabled
        self.active = active
        reconcile()
    }

    func retry() {
        failed = false
        reconcile()
    }

    func freeze() -> RollingVideoBuffer? {
        suspended = true
        buffer?.freeze()
        let snapshot = buffer
        buffer = nil
        directory = nil // Ownership transfers to the report coordinator.
        status = BugReportStrings.text("bug_recording_paused")
        reconcile()
        return snapshot
    }

    func resume() {
        suspended = false
        reconcile()
    }

    private func reconcile() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await settle()
            worker = nil
        }
    }

    private func settle() async {
        // Serializes ReplayKit start/stop calls across consent and app lifecycle changes.
        while true {
            let wanted = enabled && active && !suspended && !failed
            // A quick dismissal can resume before the stop task runs. The old
            // capture still has to stop because its buffer belongs to the report.
            let captureWasFrozen = ownsCapture && buffer == nil
            if wanted == ownsCapture && !captureWasFrozen { return }
            if !wanted || captureWasFrozen {
                buffer?.freeze()
                if ownsCapture {
                    await recorder.stopCapture()
                    ownsCapture = false
                }
                isRecording = false
                if let buffer, let directory {
                    _ = try? await buffer.snapshot()
                    files.remove(directory)
                }
                buffer = nil
                directory = nil
                if !failed { status = BugReportStrings.text(suspended ? "bug_recording_paused" : "bug_recording_off") }
                continue
            }
            guard recorder.isAvailable, !recorder.isRecording else {
                failed = true
                status = BugReportStrings.text("bug_recording_unavailable")
                return
            }
            do {
                let directory = try files.directory()
                let buffer = RollingVideoBuffer(directory: directory)
                self.directory = directory
                self.buffer = buffer
                status = BugReportStrings.text("bug_recording_starting")
                try await recorder.startCapture(handler: Self.handler(buffer: buffer) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.buffer === buffer else { return }
                        self.failed = true
                        self.status = message
                        self.reconcile()
                    }
                })
                ownsCapture = true
                isRecording = true
                status = BugReportStrings.text("bug_recording_active")
            } catch {
                failed = true
                buffer?.freeze()
                if let buffer { _ = try? await buffer.snapshot() }
                if let directory { files.remove(directory) }
                buffer = nil
                directory = nil
                status = error.localizedDescription
                return
            }
        }
    }

    // Construct outside MainActor: ReplayKit delivers samples on its capture queue.
    nonisolated private static func handler(
        buffer: RollingVideoBuffer,
        onError: @escaping @Sendable (String) -> Void
    ) -> @Sendable (CMSampleBuffer, RPSampleBufferType, (any Error)?) -> Void {
        { sample, type, error in
            if let error { onError(error.localizedDescription); return }
            if type == .video {
                buffer.ingest(sample)
                if let failure = buffer.takeFailure() { onError(failure) }
            }
        }
    }
}

#endif
