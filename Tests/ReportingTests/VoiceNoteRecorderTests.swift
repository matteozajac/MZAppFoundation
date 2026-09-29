import Foundation
import Testing
@testable import MZAppFoundationReporting

struct VoiceNoteRecorderTests {
    @MainActor @Test func rejectsUnreadableAndTooShortFiles() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = VoiceNoteRecorder(directory: root)
        let unreadable = root.appendingPathComponent("invalid.m4a")
        try Data("invalid audio".utf8).write(to: unreadable)
        #expect(throws: (any Error).self) { try recorder.acceptCompletedRecording(at: unreadable) }
        #expect(!recorder.hasRecording)
        let short = try VoiceReportTests.makeAudio(in: root, seconds: 0.1)
        #expect(throws: (any Error).self) { try recorder.acceptCompletedRecording(at: short) }
        #expect(!recorder.hasRecording)
        #expect(recorder.duration == 0)
    }

    @MainActor @Test func acceptsFiveMinutesAndRejectsLongerFiles() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = VoiceNoteRecorder(directory: root)
        let allowed = try VoiceReportTests.makeAudio(in: root, seconds: 300)
        try recorder.acceptCompletedRecording(at: allowed)
        #expect(recorder.duration <= 300)
        #expect(recorder.duration > 299)
        #expect(recorder.hasRecording)
        recorder.remove()
        let tooLong = try VoiceReportTests.makeAudio(in: root, seconds: 301)
        #expect(throws: (any Error).self) { try recorder.acceptCompletedRecording(at: tooLong) }
        #expect(!recorder.hasRecording)
    }

    @MainActor @Test func rejectsFilesOutsideTheReportDirectory() throws {
        let root = try directory()
        let elsewhere = try directory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let recorder = VoiceNoteRecorder(directory: root)
        let audio = try VoiceReportTests.makeAudio(in: elsewhere)
        #expect(throws: (any Error).self) { try recorder.acceptCompletedRecording(at: audio) }
        recorder.cancel()
        #expect(FileManager.default.fileExists(atPath: audio.path))
    }

    @MainActor @Test func cancellationWhilePermissionIsPendingCannotStartRecordingLater() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var response: CheckedContinuation<Bool, Never>?
        let recorder = VoiceNoteRecorder(directory: root, requestPermission: {
            await withCheckedContinuation { response = $0 }
        })
        let request = Task { await recorder.start() }
        while response == nil { await Task.yield() }
        #expect(recorder.isPreparing)
        #expect(recorder.hasEdits)
        recorder.cancel()
        response?.resume(returning: true)
        await request.value
        #expect(!recorder.isPreparing)
        #expect(!recorder.isRecording)
        #expect(!recorder.hasEdits)
        #expect(recorder.url == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
