import Foundation

public enum LogLevel: String, Sendable { case debug, info, notice, warning, error }

public struct LogEntry: Equatable, Sendable {
    public let level: LogLevel
    public let category: String
    /// Technical message authored by the app. Never pass user-authored text or raw error descriptions.
    public let message: String
    public let metadata: [String: TelemetryValue]
    public init(_ message: String, level: LogLevel = .info, category: String = "app",
                metadata: [String: TelemetryValue] = [:]) {
        self.message = message
        self.level = level
        self.category = category
        self.metadata = metadata
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
        LogEntry(entry.message, level: entry.level, category: entry.category, metadata: sanitize(entry.metadata))
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
