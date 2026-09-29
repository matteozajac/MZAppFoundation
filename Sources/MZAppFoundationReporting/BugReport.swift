#if os(iOS)
import Foundation
import UIKit

public enum BugLogScope: String, CaseIterable, Sendable {
    case currentSession, allSessions
}

/// Implemented by the Pulse adapter; other hosts can supply their own log format.
@MainActor public protocol BugReportAttachmentProvider {
    func exportLogs(to directory: URL, scope: BugLogScope) async throws -> URL
}

public enum BugReportStrings {
    public static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "Bug reporter")
    }
}

struct BugReport: Codable, Sendable {
    var format = "bug-reporter"
    var schemaVersion = 2
    let id: UUID
    let capturedAt: Date
    var title = ""
    var description = ""
    var steps = ""
    var expectedResult = ""
    var severity = "unspecified"
    var metadata: [String: String]
    var attachments: [String] = []
    var attachmentStatus: [String: String] = [:]
    var attachmentErrors: [String: String] = [:]
    var recordingDuration: Double?
    var voiceNote: VoiceNoteMetadata?
    var screenshotCapturedAt: Date?
    var logScope = BugLogScope.currentSession.rawValue

    var hasEdits: Bool {
        !title.isEmpty || !description.isEmpty || !steps.isEmpty || !expectedResult.isEmpty || severity != "unspecified"
    }

    var text: String {
        """
        \(title.isEmpty ? "Voice bug report" : title)

        \(description)

        Steps to reproduce: \(steps)
        Expected result: \(expectedResult)
        Severity: \(severity)
        Report: \(id.uuidString)
        Captured: \(capturedAt.ISO8601Format())
        Screenshot captured: \(screenshotCapturedAt?.ISO8601Format() ?? "—")
        Log scope: \(logScope)
        Video duration: \(recordingDuration.map { String(format: "%.1f s", $0) } ?? "—")
        Voice note: \(voiceNote.map { "\($0.filename) (\(String(format: "%.1f s", $0.duration))); transcribe on Mac before triage" } ?? "—")
        \(metadata.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
        Attachments: \(attachments.joined(separator: ", "))
        \(attachmentStatus.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
        \(attachmentErrors.sorted { $0.key < $1.key }.map { "\($0.key) unavailable: \($0.value)" }.joined(separator: "\n"))
        """
    }

    @MainActor static func make(metadata extra: [String: String]) -> Self {
        var info = extra
        info.merge([
            "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? Bundle.main.bundleIdentifier ?? "App",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "device": deviceIdentifier,
            "os": UIDevice.current.systemVersion,
            "locale": Locale.current.identifier
        ]) { _, automatic in automatic }
        return Self(id: UUID(), capturedAt: Date(), metadata: info)
    }

    private static var deviceIdentifier: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

/// Voice narration is separate from the silent recent-activity video.
struct VoiceNoteMetadata: Codable, Sendable {
    let filename: String
    let duration: Double
    var codec = "aac"
    var sampleRate = 24_000
    var channels = 1
    var bitRate: Int? = nil
    var transcriptionRequired = true
}

struct VideoSegment: Sendable {
    let url: URL
    let start: Double
    var end: Double
    var bytes: Int
}

/// Pure retention policy, shared by the encoder and its tests.
enum VideoRetention {
    static let duration: Double = 60
    static let byteLimit = 32 * 1024 * 1024

    static func retained(_ segments: [VideoSegment], endingAt end: Double, byteLimit: Int = byteLimit) -> [VideoSegment] {
        var result = segments.filter { $0.end > end - duration }
        var bytes = result.reduce(0) { $0 + $1.bytes }
        while bytes > byteLimit, !result.isEmpty {
            bytes -= result.removeFirst().bytes
        }
        return result
    }

    static func trim(start: Double, end: Double, available: Double) -> ClosedRange<Double> {
        let upper = max(0, min(available, duration, end))
        return max(0, min(start, upper))...upper
    }
}

#endif
