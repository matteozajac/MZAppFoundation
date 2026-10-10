import Foundation
import CoreData
import OSLog
import MZAppFoundation
import Pulse

@MainActor public final class PulseLogger: AppLogging {
    private let redaction: RedactionPolicy
    private let store: LoggerStore
    public init(redaction: RedactionPolicy = .init(), store: LoggerStore = .shared) {
        self.redaction = redaction
        self.store = store
    }
    public func log(_ entry: LogEntry) {
        let entry = redaction.sanitize(entry)
        let level: LoggerStore.Level = switch entry.level {
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        }
        var metadata = entry.metadata.mapValues { $0.rendered }
        if let error = entry.error {
            for (index, cause) in error.causes.enumerated() {
                let prefix = "error.cause.\(index)"
                metadata[prefix + ".type"] = cause.type
                metadata[prefix + ".domain"] = cause.domain
                metadata[prefix + ".code"] = String(cause.code)
                metadata[prefix + ".message"] = cause.message
            }
            metadata["error.stack"] = error.stack.origin.rawValue
            for (index, symbol) in error.stack.symbols.enumerated() {
                metadata[String(format: "error.stack.%02d", index)] = symbol
            }
        }
        // Pulse 5.2.1's public storeMessage strips ALL whitespace from metadata.
        // Preserve its normal insertion/event/session path, then correct only
        // the affected row through Pulse's public Core Data write context.
        // Separate frame fields avoid its newline-delimited metadata format.
        let needsCorrection = metadata.values.contains { $0.contains(where: \.isWhitespace) }
        let marker = UUID().uuidString
        var stored = metadata
        if needsCorrection { stored["mz_record_id"] = marker }
        store.storeMessage(label: entry.category, level: level, message: entry.message,
                           metadata: stored.mapValues { .string($0) }, file: entry.source.file,
                           function: entry.source.function, line: entry.source.line)
        if needsCorrection { preserveMetadata(metadata, marker: marker) }
    }

    private func preserveMetadata(_ metadata: [String: String], marker: String) {
        let context = store.backgroundContext
        // Queue confinement and FIFO ordering ensure insertion precedes correction,
        // including when a caller configures a synchronous Pulse store.
        // PulseUI observes saves on the main actor. Waiting synchronously here
        // can deadlock while that observer is merging this background save.
        context.perform {
            do {
                let request = NSFetchRequest<LoggerMessageEntity>(entityName: "LoggerMessageEntity")
                request.predicate = NSPredicate(format: "rawMetadata CONTAINS %@", "mz_record_id: " + marker)
                request.fetchLimit = 1
                guard let message = try context.fetch(request).first else { return }
                message.rawMetadata = metadata.sorted { $0.key < $1.key }.map { key, value in
                    let key = key.replacingOccurrences(of: ":", with: "").components(separatedBy: .newlines).joined()
                    let value = value.components(separatedBy: .newlines).joined(separator: " ")
                    return "\(key): \(value)"
                }.joined(separator: "\n")
                try context.save()
            } catch {
                // Logging failure must not recursively enter the diagnostics router.
                Logger(subsystem: "MZAppFoundation", category: "Pulse").error("Unable to preserve Pulse metadata formatting")
            }
        }
    }

    /// Await queued insertion/metadata repair when inspecting or exporting logs.
    /// Ordinary logging never waits on a Core Data queue from the main actor.
    public func flush() async {
        await store.backgroundContext.perform {}
    }
}

@MainActor public final class LocalTelemetryEngine: AnalyticsEngine, DiagnosticsEngine {
    public let delivery = DeliveryKind.local
    private let logger: any AppLogging
    public init(logger: any AppLogging) { self.logger = logger }
    public func setEnabled(_ enabled: Bool) {}
    public func record(_ event: TelemetryEvent) -> EngineResult {
        logger.log(LogEntry(event.name, category: "analytics", metadata: event.properties))
        return .recorded
    }
    public func record(_ issue: DiagnosticIssue) -> EngineResult {
        logger.log(LogEntry(issue.code, level: .error, category: issue.category, metadata: issue.metadata,
                            error: issue.error, source: issue.source))
        return .recorded
    }
    public func breadcrumb(_ event: TelemetryEvent) {
        logger.log(LogEntry(event.name, level: .debug, category: "breadcrumb", metadata: event.properties))
    }
}

@MainActor public enum LocalServices {
    public static func make(configuration: AppConfiguration, schema: TelemetrySchema,
                            purchases: any PurchaseProviding = MockPurchases(),
                            defaults: UserDefaults = .standard, redaction: RedactionPolicy = .init(),
                            foundationDiagnostics: FoundationDiagnostics = .init(),
                            additionalAnalytics: [any AnalyticsEngine] = [],
                            additionalDiagnostics: [any DiagnosticsEngine] = []) -> AppServices {
        let logger = PulseLogger(redaction: redaction)
        let engine = LocalTelemetryEngine(logger: logger)
        return AppServices(configuration: configuration,
                           telemetry: Telemetry(configuration: configuration, schema: schema,
                                                analytics: [engine] + additionalAnalytics,
                                                diagnostics: [engine] + additionalDiagnostics, redaction: redaction),
                           logger: logger, purchases: purchases,
                           developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults),
                           foundationDiagnostics: foundationDiagnostics)
    }
}
