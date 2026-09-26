import Foundation

public enum LogLevel: String, Sendable { case debug, info, notice, warning, error }

public struct LogEntry: Equatable, Sendable {
    public let level: LogLevel
    public let category: String
    /// Technical message authored by the app. Never pass user-authored text or raw error descriptions.
    public let message: String
    public let metadata: [String: TelemetryValue]
    public let error: ErrorSnapshot?
    public let source: LogSource
    public let reportsToDiagnostics: Bool
    public init(_ message: String, level: LogLevel = .info, category: String = "app",
                metadata: [String: TelemetryValue] = [:], error: ErrorSnapshot? = nil,
                source: LogSource? = nil, reportsToDiagnostics: Bool = true,
                file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.message = message
        self.level = level
        self.category = category
        self.metadata = metadata
        self.error = error
        self.source = source ?? LogSource(file: file, function: function, line: line)
        self.reportsToDiagnostics = reportsToDiagnostics
    }
}

public struct RedactionPolicy: Equatable, Sendable {
    public var additionalSensitiveKeys: Set<String>
    public init(additionalSensitiveKeys: Set<String> = []) {
        self.additionalSensitiveKeys = Set(additionalSensitiveKeys.map { $0.lowercased() })
    }
    public static func isSensitive(_ key: String) -> Bool {
        let lower = key.lowercased()
        return ["token", "password", "secret", "authorization", "cookie", "receipt", "transaction",
                "email", "phone", "userid", "user_id", "prompt", "transcript", "response", "assertion",
                "signature", "appcheck", "app-check"].contains { lower.contains($0) }
    }
    public func sanitize(_ metadata: [String: TelemetryValue]) -> [String: TelemetryValue] {
        metadata.filter { !Self.isSensitive($0.key) && !additionalSensitiveKeys.contains($0.key.lowercased()) }
    }
    public func sanitize(_ entry: LogEntry) -> LogEntry {
        LogEntry(entry.message, level: entry.level, category: entry.category, metadata: sanitize(entry.metadata),
                 error: entry.error, source: entry.source, reportsToDiagnostics: entry.reportsToDiagnostics)
    }
}

@MainActor public protocol AppLogging: AnyObject {
    func log(_ entry: LogEntry)
}

@MainActor public final class RecordingLogger: AppLogging {
    public private(set) var entries: [LogEntry] = []
    private let redaction: RedactionPolicy
    public init(redaction: RedactionPolicy = .init()) { self.redaction = redaction }
    public func log(_ entry: LogEntry) { entries.append(redaction.sanitize(entry)) }
    public func reset() { entries.removeAll() }
}

/// Error logs use the same diagnostics fan-out as explicit diagnostic issues.
/// The local diagnostics engine must retain the raw sink, not this router.
@MainActor public final class DiagnosticsLogger: AppLogging {
    private let local: any AppLogging
    private let diagnostics: any DiagnosticsReporting
    public init(local: any AppLogging, diagnostics: any DiagnosticsReporting) {
        self.local = local
        self.diagnostics = diagnostics
    }
    public func log(_ entry: LogEntry) {
        if entry.level == .error && entry.reportsToDiagnostics {
            diagnostics.record(DiagnosticIssue(code: entry.message, category: entry.category,
                                               metadata: entry.metadata, error: entry.error, source: entry.source))
        } else {
            local.log(entry)
        }
    }
}

public extension AppLogging {
    func error(_ message: String, error: any Error, category: String = "app",
               metadata: [String: TelemetryValue] = [:],
               file: String = #fileID, function: String = #function, line: UInt = #line) {
        guard !ErrorSnapshot.isCancellation(error) else { return }
        log(LogEntry(message, level: .error, category: category, metadata: metadata,
                     error: ErrorSnapshot(error, file: file, function: function, line: line), source: LogSource(file: file, function: function, line: line)))
    }
    func error(_ message: String, category: String = "app", metadata: [String: TelemetryValue] = [:],
               file: String = #fileID, function: String = #function, line: UInt = #line) {
        log(LogEntry(message, level: .error, category: category, metadata: metadata,
                     source: LogSource(file: file, function: function, line: line)))
    }
}
