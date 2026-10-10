import AVFoundation
import CoreData
import Pulse
import Testing
import SQLite3
import UIKit
@testable import MZAppFoundationReporting
import MZAppFoundationLocal

struct BugReporterTests {
    @MainActor @Test func screenVideoDefaultsOffEvenWithDeveloperAccess() async throws {
        let suite = "reporting.video.default." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = BugReportCoordinator(attachmentProvider: FixtureProvider(), defaults: defaults)
        #expect(!coordinator.recordingEnabled)
        coordinator.update(developerMode: true, isActive: true)
        coordinator.retryRecording()
        await Task.yield()
        #expect(!coordinator.isRecording)
        #expect(!coordinator.canRetryRecording)
        #expect(defaults.object(forKey: "BugReporter.recordRecentActivity") == nil)
        coordinator.update(developerMode: false, isActive: false)
    }

    @MainActor @Test(arguments: [true, false]) func screenVideoPreservesExplicitChoice(enabled: Bool) throws {
        let suite = "reporting.video.saved." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(enabled, forKey: "explicit.video")
        let coordinator = BugReportCoordinator(attachmentProvider: FixtureProvider(), defaults: defaults,
                                               preferenceKey: "explicit.video")
        #expect(coordinator.recordingEnabled == enabled)
    }

    @MainActor @Test func screenVideoOptInAndRevocationPersistAcrossRelaunch() throws {
        let suite = "reporting.video.lifecycle." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "explicit.video"
        let coordinator = BugReportCoordinator(attachmentProvider: FixtureProvider(), defaults: defaults,
                                               preferenceKey: key)
        coordinator.recordingEnabled = true
        #expect(defaults.object(forKey: key) as? Bool == true)
        let relaunched = BugReportCoordinator(attachmentProvider: FixtureProvider(), defaults: defaults,
                                              preferenceKey: key)
        #expect(relaunched.recordingEnabled)
        relaunched.recordingEnabled = false
        #expect(defaults.object(forKey: key) as? Bool == false)
        let afterRevocation = BugReportCoordinator(attachmentProvider: FixtureProvider(), defaults: defaults,
                                                  preferenceKey: key)
        #expect(!afterRevocation.recordingEnabled)
    }

    @Test func rollingRetentionKeepsBoundaryAndEnforcesByteLimit() {
        let segments: [VideoSegment] = (0..<25).map { index in
            let start = Double(index) * 5
            let end = start + 5
            let url = URL(filePath: "/\(index).mp4")
            return VideoSegment(url: url, start: start, end: end, bytes: 1_000)
        }
        let kept = VideoRetention.retained(segments, endingAt: 123)
        #expect(kept.first?.start == 60)
        #expect(kept.count == 13)
        let limited = VideoRetention.retained(segments, endingAt: 123, byteLimit: 3_000)
        #expect(limited.count == 3)
        #expect(limited.last?.url == segments.last?.url)
        #expect(VideoRetention.retained(segments, endingAt: 123, byteLimit: 0).isEmpty)
    }

    @Test func trimNeverExceedsAvailableMinute() {
        #expect(VideoRetention.trim(start: -2, end: 100, available: 120) == 0...60)
        #expect(VideoRetention.trim(start: 3, end: 40, available: 12) == 3...12)
        #expect(VideoRetention.trim(start: 90, end: 40, available: 12) == 12...12)
    }

    @Test func cleanupCannotRemoveOutsideOwnedRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try ReportFiles(root: root)
        let directory = try files.directory()
        let sibling = root.appendingPathExtension("keep")
        try Data([1]).write(to: sibling)
        defer { try? FileManager.default.removeItem(at: sibling) }
        files.remove(sibling)
        #expect(FileManager.default.fileExists(atPath: sibling.path))
        files.clearAbandoned()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor @Test func pulseArchivePreservesMessagesAndNetworkBodies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LoggerStore(storeURL: root.appendingPathComponent("store"), options: [.create, .synchronous])
        defer { try? store.close() }
        store.storeMessage(label: "QA", level: .error, message: "Current session error")
        store.storeMessage(label: "QA", level: .info, message: "Older session")
        try await store.backgroundContext.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "LoggerMessageEntity")
            request.predicate = NSPredicate(format: "text == %@", "Older session")
            for message in try store.backgroundContext.fetch(request) {
                message.setValue(UUID(), forKey: "session")
            }
            try store.backgroundContext.save()
        }
        var request = URLRequest(url: URL(string: "https://example.test/bug")!)
        request.httpMethod = "POST"
        request.httpBody = Data(String(repeating: "request-body", count: 5000).utf8)
        store.storeRequest(request, response: HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil), error: nil, data: Data("response-body".utf8))
        let provider = PulseReportAttachmentProvider(store: store)
        for scope in BugLogScope.allCases {
            let output = root.appendingPathComponent(scope.rawValue)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let url = try await provider.exportLogs(to: output, scope: scope)
            #expect(url.pathExtension == "pulse")
            let unpacked = try unpackPulse(url, manifest: root.appendingPathComponent("store/manifest.json"))
            let reopened = try LoggerStore(storeURL: unpacked, options: [.readonly])
            defer { try? reopened.close() }
            let messages = try reopened.messages()
            #expect(messages.contains { $0.text == "Current session error" })
            #expect(messages.contains { $0.text == "Older session" } == (scope == .allSessions))
            let tasks = try reopened.tasks()
            #expect(tasks.count == 1)
            let task = try #require(tasks.first)
            #expect(task.statusCode == 500)
            #expect(task.requestBody?.data == request.httpBody)
            #expect(task.responseBody?.data == Data("response-body".utf8))
        }
    }

    @Test func twoMinuteBufferExportsFinalMinuteAndIgnoresFrozenFrames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let buffer = RollingVideoBuffer(directory: root)
        for second in 0..<125 {
            buffer.ingest(try sample(at: Double(second), landscape: second >= 100))
            if second % 5 == 0 { _ = try await buffer.snapshot() }
        }
        buffer.freeze()
        buffer.ingest(try sample(at: 300, landscape: false))
        let segments = try await buffer.snapshot()
        #expect(try #require(segments.last).end < 125)
        #expect(segments.count <= 13)
        #expect(segments.reduce(0) { $0 + $1.bytes } < VideoRetention.byteLimit)
        let movie = root.appendingPathComponent("combined.mp4")
        let exporter = VideoExporter()
        let duration = try await exporter.combine(segments, to: movie)
        #expect(duration > 59 && duration <= 60)
        let asset = AVURLAsset(url: movie)
        #expect(try await asset.load(.duration).seconds <= 60.01)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let trimmed = root.appendingPathComponent("trimmed.mp4")
        try await exporter.trim(movie, range: 10...20, to: trimmed)
        let trimmedDuration = try await AVURLAsset(url: trimmed).load(.duration).seconds
        #expect(abs(trimmedDuration - 10) < 0.1)
    }

    @Test func shortRecordingAndEmptyBuffer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let buffer = RollingVideoBuffer(directory: root)
        buffer.ingest(try sample(at: 10, landscape: false))
        buffer.ingest(try sample(at: 12, landscape: false))
        buffer.freeze()
        let segments = try await buffer.snapshot()
        let duration = try await VideoExporter().combine(segments, to: root.appendingPathComponent("short.mp4"))
        #expect(duration > 2 && duration < 3)
        await #expect(throws: (any Error).self) {
            try await VideoExporter().combine([], to: root.appendingPathComponent("empty.mp4"))
        }
    }

    @Test func encoderFailureIsReportedOnceAndDoesNotAcceptMoreFrames() async throws {
        let buffer = RollingVideoBuffer(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        buffer.ingest(try sample(at: 1, landscape: false))
        #expect(buffer.takeFailure() != nil)
        #expect(buffer.takeFailure() == nil)
        buffer.ingest(try sample(at: 2, landscape: false))
        buffer.freeze()
        await #expect(throws: (any Error).self) { try await buffer.snapshot() }
    }

    @MainActor @Test func reportMetadataAndAttachmentSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = ReportDraft(report: .make(metadata: ["environment": "test"]), directory: root, provider: FixtureProvider())
        draft.shareAsZIP = false
        draft.report.title = "A reproducible failure"
        draft.report.description = "Details"
        draft.includeScreenshot = false
        draft.includeVideo = false
        await draft.prepareLogs()
        let items = try await draft.shareItems()
        let files = items.compactMap { $0 as? URL }
        #expect(files.contains { $0.pathExtension == "pulse" })
        let json = try #require(files.first { $0.pathExtension == "json" })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(BugReport.self, from: Data(contentsOf: json))
        #expect(report.title == draft.report.title)
        #expect(report.metadata["environment"] == "test")
        #expect(report.attachments == ["logs.pulse"])
        draft.includeLogs = false
        let withoutLogs = try await draft.shareItems().compactMap { $0 as? URL }
        #expect(!withoutLogs.contains { $0.pathExtension == "pulse" })
    }

    @MainActor @Test func changingScopeCannotPublishStaleLogsAndCleanupWaitsForExports() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = GatedProvider()
        let draft = ReportDraft(report: .make(metadata: [:]), directory: root, provider: provider)
        let first = Task { await draft.prepareLogs() }
        await provider.waitForRequests(1)
        draft.logScope = .allSessions
        let second = Task { await draft.prepareLogs() }
        await provider.waitForRequests(2)
        var idle = false
        let waiter = Task { await draft.waitForExports(); idle = true }
        try provider.complete(1)
        await second.value
        #expect(draft.logs?.lastPathComponent == "allSessions.pulse")
        #expect(!idle)
        try provider.complete(0)
        await first.value
        await waiter.value
        #expect(idle)
        #expect(draft.logs?.lastPathComponent == "allSessions.pulse")
        #expect(!draft.preparingLogs)
    }

    // Pulse 5 exports a SQLite document, while LoggerStore's public initializer
    // accepts unpacked stores. Decode the documented native payload for round-trip QA.
    private func unpackPulse(_ url: URL, manifest: URL) throws -> URL {
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, "SELECT ZKEY, ZDATA FROM ZPULSEBLOBENTITY", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let directory = url.deletingLastPathComponent().appendingPathComponent("unpacked")
        let blobs = directory.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: manifest, to: directory.appendingPathComponent("manifest.json"))
        while sqlite3_step(statement) == SQLITE_ROW {
            let key = String(cString: try #require(sqlite3_column_text(statement, 0)))
            let bytes = try #require(sqlite3_column_blob(statement, 1))
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            if key == "database" {
                let decompressed = try (data as NSData).decompressed(using: .lzfse) as Data
                try decompressed.write(to: directory.appendingPathComponent("logs.sqlite"))
            } else if key.count == 40 {
                try data.write(to: blobs.appendingPathComponent(key))
            }
        }
        return directory
    }

    func sample(at seconds: Double, landscape: Bool) throws -> CMSampleBuffer {
        var optionalPixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 64, 128, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optionalPixel) == kCVReturnSuccess)
        let pixel = try #require(optionalPixel)
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), Int32(Int(seconds) % 255), CVPixelBufferGetDataSize(pixel))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 15), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample)
        let result = try #require(sample)
        CMSetAttachment(result, key: "RPVideoSampleOrientationKey" as CFString, value: NSNumber(value: landscape ? 6 : 1), attachmentMode: kCMAttachmentMode_ShouldPropagate)
        return result
    }
}

@MainActor private struct FixtureProvider: BugReportAttachmentProvider {
    func exportLogs(to directory: URL, scope: BugLogScope) async throws -> URL {
        let url = directory.appendingPathComponent("logs.pulse")
        try Data([1, 2]).write(to: url)
        return url
    }
}

@MainActor private final class GatedProvider: BugReportAttachmentProvider {
    private var requests: [(URL, BugLogScope, CheckedContinuation<URL, any Error>)] = []
    private var started: [(Int, CheckedContinuation<Void, Never>)] = []

    func exportLogs(to directory: URL, scope: BugLogScope) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((directory, scope, continuation))
            let ready = started.filter { $0.0 <= requests.count }
            started.removeAll { $0.0 <= requests.count }
            for entry in ready { entry.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { started.append((count, $0)) }
    }

    func complete(_ index: Int) throws {
        let (directory, scope, continuation) = requests[index]
        let url = directory.appendingPathComponent(scope.rawValue + ".pulse")
        try Data([1]).write(to: url)
        continuation.resume(returning: url)
    }
}
