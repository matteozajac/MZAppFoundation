import Foundation
import Pulse
import Testing
import UIKit
import zlib
@testable import MZAppFoundationReporting
import MZAppFoundationLocal

struct ReportArchiveTests {
    @MainActor @Test func audioOnlyZIPPreservesOriginalAACAndTranscriptionMarker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LoggerStore(storeURL: root.appendingPathComponent("store"), options: [.create, .synchronous])
        defer { try? store.close() }
        let draft = ReportDraft(report: .make(metadata: ["environment": "synthetic-audio-test"]), directory: root,
                                provider: PulseReportAttachmentProvider(store: store), archivePrefix: "jod-ios")
        draft.includeScreenshot = false
        draft.includeVideo = false
        draft.includeLogs = false
        let audio = try VoiceReportTests.makeAudio(in: root)
        try draft.voiceNote.acceptCompletedRecording(at: audio)
        let archive = try #require(try await draft.shareItems().first as? URL)
        let contents = try zipContents(archive)
        #expect(Set(contents.keys) == ["report.txt", "report.json", "voice-note.m4a"])
        #expect(contents["voice-note.m4a"] == (try Data(contentsOf: audio)))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(BugReport.self, from: #require(contents["report.json"]))
        #expect(report.title.isEmpty)
        #expect(report.voiceNote?.transcriptionRequired == true)
        #expect(report.attachmentStatus["audio"] == "included")
        #if compiler(>=6.2)
        Attachment.record(Array(try Data(contentsOf: archive)), named: archive.lastPathComponent)
        #endif
    }

    @MainActor @Test func defaultZIPRoundTripsNativeLogsMediaAndSelections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LoggerStore(storeURL: root.appendingPathComponent("store"), options: [.create, .synchronous])
        defer { try? store.close() }
        store.storeMessage(label: "QA", level: .error, message: "ZIP fixture: saving the wedding failed")
        var request = URLRequest(url: URL(string: "https://example.test/wedding")!)
        request.httpMethod = "POST"
        request.httpBody = Data(String(repeating: "request-body", count: 5000).utf8)
        store.storeRequest(request, response: HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil), error: nil, data: Data("fixture-response-body".utf8))
        let report = BugReport.make(metadata: ["environment": "test"])
        let draft = ReportDraft(report: report, directory: root, provider: PulseReportAttachmentProvider(store: store), archivePrefix: "jod-ios")
        draft.report.title = "Saving failed"
        draft.report.description = "QA fixture for archive import"
        let screenshot = root.appendingPathComponent("screenshot.png")
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }.pngData())
        try png.write(to: screenshot)
        draft.screenshot = screenshot
        let buffer = RollingVideoBuffer(directory: root)
        buffer.ingest(try BugReporterTests().sample(at: 0, landscape: false))
        buffer.ingest(try BugReporterTests().sample(at: 2, landscape: false))
        buffer.freeze()
        await draft.prepareVideo(buffer)
        #expect(draft.video != nil)
        await draft.prepareLogs()
        #expect(draft.shareAsZIP)
        let items = try await draft.shareItems()
        #expect(items.count == 1)
        let archive = try #require(items.first as? URL)
        #expect(archive.lastPathComponent == "jod-ios-\(report.id.uuidString.lowercased()).zip")
        let contents = try zipContents(archive)
        #expect(Set(contents.keys) == ["report.txt", "report.json", "logs.pulse", "screenshot.png", "recording.mp4"])
        #expect(contents["screenshot.png"] == png)
        #expect(contents["logs.pulse"] == (try Data(contentsOf: #require(draft.logs))))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BugReport.self, from: #require(contents["report.json"]))
        #expect(decoded.id == report.id)
        #expect(decoded.schemaVersion == 2)
        #expect(decoded.format == "bug-reporter")
        #expect(decoded.attachmentStatus == ["logs": "included", "screenshot": "included", "video": "included", "audio": "excluded"])
        #expect(decoded.recordingDuration ?? 0 > 2)
        // Synthetic evidence only; export from the xcresult for independent skill QA.
        #if compiler(>=6.2)
        Attachment.record(Array(try Data(contentsOf: archive)), named: archive.lastPathComponent)
        #endif
        draft.includeScreenshot = false
        draft.includeVideo = false
        draft.logs = nil
        draft.logsError = "Fixture log export failure"
        let second = try #require(try await draft.shareItems().first as? URL)
        #expect(second != archive)
        #expect(second.lastPathComponent == archive.lastPathComponent)
        let secondContents = try zipContents(second)
        #expect(Set(secondContents.keys) == ["report.txt", "report.json"])
        let secondReport = try decoder.decode(BugReport.self, from: #require(secondContents["report.json"]))
        #expect(secondReport.attachmentStatus == ["logs": "unavailable", "screenshot": "excluded", "video": "excluded", "audio": "excluded"])
        #expect(secondReport.attachmentErrors == ["logs": "Fixture log export failure"])
        #expect(secondReport.attachments.isEmpty)
    }

    @Test func archiveRejectsDuplicateNamesAndLinksWithoutRemovingOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("report.txt")
        try Data("fixture".utf8).write(to: file)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let archive = ReportArchive()
        for files in [[file, file], [link], [root.appendingPathComponent("missing")]] {
            await #expect(throws: (any Error).self) {
                try await archive.create(files: files, in: root, name: "report")
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("report").path))
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("report.zip").path))
            #expect(try Data(contentsOf: file) == Data("fixture".utf8))
        }
    }

    @Test func archivePrefixCannotEscapeOutputDirectory() {
        let id = UUID()
        #expect(ReportArchive.name(prefix: "../JOD-iOS/", id: id) == "jod-ios-\(id.uuidString.lowercased())")
        #expect(ReportArchive.name(prefix: "../", id: id) == "bug-report-\(id.uuidString.lowercased())")
    }

    @MainActor @Test func diagnosticsSnapshotIsIncludedInZIPAndCanBeExcluded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LoggerStore(storeURL: root.appendingPathComponent("store"), options: [.create, .synchronous])
        defer { try? store.close() }
        let snapshot = Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":1,"providers":[{"projectID":"proj_fixture"}]}"#.utf8)
        let draft = ReportDraft(report: .make(metadata: [:]), directory: root,
                                provider: PulseReportAttachmentProvider(store: store), diagnostics: .available(snapshot))
        draft.report.title = "Diagnostics fixture"
        draft.includeScreenshot = false; draft.includeVideo = false; draft.includeLogs = false
        let archive = try #require(try await draft.shareItems().first as? URL)
        let contents = try zipContents(archive)
        #expect(contents["diagnostics.json"] == snapshot)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let included = try decoder.decode(BugReport.self, from: #require(contents["report.json"]))
        #expect(included.attachments == ["diagnostics.json"])
        #expect(included.attachmentStatus["diagnostics"] == "included")
        draft.includeDiagnostics = false
        let second = try #require(try await draft.shareItems().first as? URL)
        let excludedContents = try zipContents(second)
        #expect(excludedContents["diagnostics.json"] == nil)
        let excluded = try decoder.decode(BugReport.self, from: #require(excludedContents["report.json"]))
        #expect(excluded.attachmentStatus["diagnostics"] == "excluded")
    }

    // Independent ZIP reader for the Foundation-produced archive. Parse the
    // central directory (local sizes may use data descriptors), inflate and CRC.
    private func zipContents(_ url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        func number(_ offset: Int, _ count: Int) throws -> Int {
            #expect(offset >= 0 && offset + count <= data.count)
            return data[offset..<(offset + count)].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        }
        let end = try #require(stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1).first { (try? number($0, 4)) == 0x06054b50 })
        var offset = try number(end + 16, 4)
        var result: [String: Data] = [:]
        for _ in 0..<(try number(end + 10, 2)) {
            #expect(try number(offset, 4) == 0x02014b50)
            let method = try number(offset + 10, 2)
            let crc = try number(offset + 16, 4)
            let compressed = try number(offset + 20, 4)
            let size = try number(offset + 24, 4)
            let nameSize = try number(offset + 28, 2)
            let name = String(decoding: data[(offset + 46)..<(offset + 46 + nameSize)], as: UTF8.self)
            let local = try number(offset + 42, 4)
            let start = try local + 30 + number(local + 26, 2) + number(local + 28, 2)
            offset += try 46 + nameSize + number(offset + 30, 2) + number(offset + 32, 2)
            if name.hasSuffix("/") || name.hasPrefix("__MACOSX/") { continue }
            let bytes = Data(data[start..<(start + compressed)])
            var content = Data(count: max(1, size))
            if method == 0 {
                content = bytes
            } else {
                #expect(method == 8)
                var stream = z_stream()
                #expect(inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
                defer { inflateEnd(&stream) }
                let status = content.withUnsafeMutableBytes { destination in
                    bytes.withUnsafeBytes { source in
                        stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(bytes.count)
                        stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(max(1, size))
                        return inflate(&stream, Z_FINISH)
                    }
                }
                #expect(status == Z_STREAM_END)
                #expect(stream.total_out == size)
                content.count = size
            }
            #expect(content.withUnsafeBytes { Int(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(content.count))) } == crc)
            let basename = URL(filePath: name).lastPathComponent
            #expect(result[basename] == nil)
            result[basename] = content
        }
        return result
    }
}
