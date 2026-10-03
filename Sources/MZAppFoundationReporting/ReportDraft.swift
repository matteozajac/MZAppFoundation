#if os(iOS)
import Observation
import UIKit

@MainActor @Observable
final class ReportDraft {
    var report: BugReport
    let directory: URL
    let voiceNote: VoiceNoteRecorder
    var screenshot: URL?
    var video: URL?
    var logs: URL?
    var screenshotError: String?
    var videoError: String?
    var logsError: String?
    var includeScreenshot = true
    var includeVideo = true
    var includeLogs = true
    var includeDiagnostics = true
    var shareAsZIP = true
    var logScope = BugLogScope.currentSession
    var videoDuration: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var preparingVideo = false
    var preparingLogs = false
    var sharing = false
    var shareError: String?
    private(set) var initialScreenshotTime: Date?
    private let provider: any BugReportAttachmentProvider
    private let exporter = VideoExporter()
    private let archive = ReportArchive()
    private let archivePrefix: String
    private let diagnostics: ReportDiagnosticsCapture
    var hasDiagnostics: Bool {
        if case .available = diagnostics { true } else { false }
    }
    var diagnosticsUnavailable: Bool {
        if case .unavailable = diagnostics { true } else { false }
    }
    private var logGeneration = UUID()
    private var activeLogExports = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForExports() async {
        guard preparingVideo || activeLogExports > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func notifyIfIdle() {
        guard !preparingVideo, activeLogExports == 0 else { return }
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    init(report: BugReport, directory: URL, provider: any BugReportAttachmentProvider, archivePrefix: String = "bug-report",
         diagnostics: ReportDiagnosticsCapture = .notProvided) {
        self.report = report
        self.directory = directory
        voiceNote = VoiceNoteRecorder(directory: directory)
        self.provider = provider
        self.archivePrefix = archivePrefix
        self.diagnostics = diagnostics
    }

    var hasEdits: Bool {
        report.hasEdits || voiceNote.hasEdits || !includeScreenshot || !includeVideo || !includeLogs || !includeDiagnostics || !shareAsZIP || logScope != .currentSession || trimStart != 0 || trimEnd != videoDuration
    }

    var canShare: Bool {
        !voiceNote.isPreparing && !voiceNote.isRecording && !preparingLogs && !preparingVideo &&
        (!report.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || voiceNote.hasRecording)
    }

    func capture(window: UIWindow) {
        do {
            guard !window.isHidden, !window.bounds.isEmpty else { throw CaptureError.failed(BugReportStrings.text("bug_screenshot_failed")) }
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            var rendered = false
            let image = renderer.image { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard rendered, let png = image.pngData() else { throw CaptureError.failed(BugReportStrings.text("bug_screenshot_failed")) }
            let url = directory.appendingPathComponent("screenshot.png")
            try png.write(to: url, options: .atomic)
            screenshot = url
            initialScreenshotTime = Date()
            screenshotError = nil
        } catch { screenshotError = error.localizedDescription }
    }

    func prepareVideo(_ buffer: RollingVideoBuffer?) async {
        guard let buffer else { videoError = BugReportStrings.text("bug_video_unavailable"); return }
        preparingVideo = true
        defer { preparingVideo = false; notifyIfIdle() }
        do {
            let segments = try await buffer.snapshot()
            let url = directory.appendingPathComponent("recording-" + UUID().uuidString + ".mp4")
            videoDuration = try await exporter.combine(segments, to: url)
            trimEnd = videoDuration
            video = url
            videoError = nil
        } catch { videoError = error.localizedDescription }
    }

    func prepareLogs() async {
        activeLogExports += 1
        defer { activeLogExports -= 1; notifyIfIdle() }
        let generation = UUID()
        logGeneration = generation
        preparingLogs = true
        logsError = nil
        do {
            let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = try await provider.exportLogs(to: folder, scope: logScope)
            guard generation == logGeneration else { return }
            logs = url
        } catch {
            guard generation == logGeneration else { return }
            logs = nil
            logsError = error.localizedDescription
        }
        if generation == logGeneration { preparingLogs = false }
    }

    func shareItems() async throws -> [Any] {
        guard canShare else { throw CaptureError.failed(BugReportStrings.text("bug_title_or_audio_help")) }
        voiceNote.stopPlayback()
        let output = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var urls: [URL] = []
        if includeScreenshot, let screenshot { urls.append(screenshot) }
        if includeLogs, let logs { urls.append(logs) }
        var report = report
        report.title = report.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch diagnostics {
        case .notProvided: break
        case .available(let data):
            if includeDiagnostics {
                let target = output.appendingPathComponent("diagnostics.json")
                try ReportDiagnosticsAttachment.validated(data).write(to: target, options: .atomic)
                urls.append(target)
                report.attachmentStatus["diagnostics"] = "included"
            } else { report.attachmentStatus["diagnostics"] = "excluded" }
        case .unavailable:
            report.attachmentStatus["diagnostics"] = includeDiagnostics ? "unavailable" : "excluded"
            if includeDiagnostics { report.attachmentErrors["diagnostics"] = "A safe diagnostics snapshot could not be created." }
        }
        if voiceNote.hasRecording, let audio = voiceNote.url {
            let target = output.appendingPathComponent("voice-note.m4a")
            // Copy the original AAC; recompression would only reduce speech quality.
            try FileManager.default.copyItem(at: audio, to: target)
            urls.append(target)
            report.voiceNote = VoiceNoteMetadata(filename: target.lastPathComponent, duration: voiceNote.duration, bitRate: voiceNote.bitRate)
            report.attachmentStatus["audio"] = "included"
        } else {
            report.voiceNote = nil
            report.attachmentStatus["audio"] = voiceNote.error == nil ? "excluded" : "unavailable"
            if let error = voiceNote.error { report.attachmentErrors["audio"] = error }
        }
        if includeVideo, let video {
            let target = output.appendingPathComponent("recording.mp4")
            let range = VideoRetention.trim(start: trimStart, end: trimEnd, available: videoDuration)
            try await exporter.trim(video, range: range, to: target)
            urls.append(target)
            report.recordingDuration = range.upperBound - range.lowerBound
        }
        report.screenshotCapturedAt = includeScreenshot ? initialScreenshotTime : nil
        report.logScope = logScope.rawValue
        report.attachments = urls.map(\.lastPathComponent)
        let attachments = [
            ("screenshot", includeScreenshot, screenshot, screenshotError),
            ("video", includeVideo, video, videoError),
            ("logs", includeLogs, logs, logsError)
        ]
        for (kind, selected, file, error) in attachments {
            report.attachmentStatus[kind] = !selected ? "excluded" : file != nil ? "included" : "unavailable"
            if selected, file == nil, let error { report.attachmentErrors[kind] = error }
        }
        let json = output.appendingPathComponent("report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: json)
        let text = output.appendingPathComponent("report.txt")
        try report.text.write(to: text, atomically: true, encoding: .utf8)
        if shareAsZIP {
            let name = ReportArchive.name(prefix: archivePrefix, id: report.id)
            return [try await archive.create(files: [text, json] + urls, in: output, name: name)]
        }
        return [report.text, text, json] + urls
    }
}

#endif
