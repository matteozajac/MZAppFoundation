import AVFoundation
import Foundation
import Testing
@testable import MZAppFoundationReporting

struct VoiceReportTests {
    @MainActor @Test func titleOrFinishedVoiceRequiredAndRemovalRestoresValidation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = makeDraft(root)
        #expect(!draft.canShare)
        draft.report.title = " \n "
        #expect(!draft.canShare)
        await #expect(throws: (any Error).self) { _ = try await draft.shareItems() }
        draft.report.title = "Failure to save"
        #expect(draft.canShare)
        draft.report.title = ""
        let audio = try Self.makeAudio(in: root)
        try draft.voiceNote.acceptCompletedRecording(at: audio)
        #expect(draft.canShare)
        #expect(draft.hasEdits)
        let items = try await draft.shareItems()
        let files = items.compactMap { $0 as? URL }
        let json = try #require(files.first { $0.pathExtension == "json" })
        let report = try decode(Data(contentsOf: json))
        #expect(report.title.isEmpty)
        #expect(report.schemaVersion == 2)
        #expect(report.voiceNote?.filename == "voice-note.m4a")
        #expect(report.voiceNote?.transcriptionRequired == true)
        #expect(report.voiceNote?.codec == "aac")
        #expect(report.voiceNote?.sampleRate == 24_000)
        #expect(report.voiceNote?.channels == 1)
        #expect((report.voiceNote?.bitRate ?? 0) > 0)
        #expect(report.voiceNote?.duration ?? 0 >= 0.9)
        #expect(report.attachmentStatus["audio"] == "included")
        #expect(report.recordingDuration == nil)
        let exported = try #require(files.first { $0.lastPathComponent == "voice-note.m4a" })
        #expect(try Data(contentsOf: exported) == Data(contentsOf: audio))
        #expect(exported != audio)

        draft.voiceNote.remove()
        #expect(!draft.canShare)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        draft.report.title = "  Written replacement  "
        #expect(draft.canShare)
        let replacement = try await draft.shareItems().compactMap { $0 as? URL }
        #expect(!replacement.contains { $0.pathExtension == "m4a" })
        let written = try decode(Data(contentsOf: #require(replacement.first { $0.pathExtension == "json" })))
        #expect(written.title == "Written replacement")
        #expect(written.voiceNote == nil)
        #expect(written.attachmentStatus["audio"] == "excluded")
    }

    @MainActor @Test func titleAndVoicePreservedAcrossRepeatedSharingAndMissingFileFails() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = makeDraft(root)
        draft.report.title = "A short title"
        draft.report.description = "Additional context"
        let audio = try Self.makeAudio(in: root)
        try draft.voiceNote.acceptCompletedRecording(at: audio)
        for _ in 0..<2 {
            let files = try await draft.shareItems().compactMap { $0 as? URL }
            let report = try decode(Data(contentsOf: #require(files.first { $0.pathExtension == "json" })))
            #expect(report.title == "A short title")
            #expect(report.description == "Additional context")
            #expect(report.voiceNote != nil)
            #expect(FileManager.default.fileExists(atPath: audio.path))
        }
        try FileManager.default.removeItem(at: audio)
        await #expect(throws: (any Error).self) { _ = try await draft.shareItems() }
    }

    @MainActor @Test func legacyTitleOnlyReportStillDecodes() throws {
        var original = BugReport.make(metadata: [:])
        original.schemaVersion = 1
        original.title = "Legacy report"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let report = try decode(encoder.encode(original))
        #expect(report.schemaVersion == 1)
        #expect(report.voiceNote == nil)
        #expect(report.title == "Legacy report")
    }

    @MainActor private func makeDraft(_ root: URL) -> ReportDraft {
        let draft = ReportDraft(report: .make(metadata: [:]), directory: root, provider: NoLogs())
        draft.shareAsZIP = false
        draft.includeScreenshot = false
        draft.includeVideo = false
        draft.includeLogs = false
        return draft
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decode(_ data: Data) throws -> BugReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BugReport.self, from: data)
    }

    static func makeAudio(in directory: URL, seconds: Double = 1) throws -> URL {
        let url = directory.appendingPathComponent("fixture-voice.m4a")
        // Closing the writer before validation finalizes the M4A container.
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000
            ])
            let frames = AVAudioFrameCount(24_000 * seconds)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = try #require(buffer.floatChannelData?[0])
            for frame in 0..<Int(frames) {
                samples[frame] = Float(sin(Double(frame) * 440 * 2 * .pi / 24_000)) * 0.2
            }
            try file.write(from: buffer)
        }
        return url
    }
}

@MainActor private struct NoLogs: BugReportAttachmentProvider {
    func exportLogs(to directory: URL, scope: BugLogScope) async throws -> URL {
        throw CocoaError(.fileNoSuchFile)
    }
}
