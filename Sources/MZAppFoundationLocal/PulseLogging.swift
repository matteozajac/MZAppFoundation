import Foundation
import MZAppFoundation
import Pulse

@MainActor public final class PulseLogger: AppLogging {
    private let redaction: RedactionPolicy
    public init(redaction: RedactionPolicy = .init()) { self.redaction = redaction }
    public func log(_ entry: LogEntry) {
        let entry = redaction.sanitize(entry)
        let level: LoggerStore.Level = switch entry.level {
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        }
        LoggerStore.shared.storeMessage(label: entry.category, level: level, message: entry.message,
                                        metadata: entry.metadata.mapValues { .string($0.rendered) })
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
        logger.log(LogEntry(issue.code, level: .error, category: issue.category, metadata: issue.metadata))
        return .recorded
    }
    public func breadcrumb(_ event: TelemetryEvent) {
        logger.log(LogEntry(event.name, level: .debug, category: "breadcrumb", metadata: event.properties))
    }
}

@MainActor public enum LocalServices {
    public static func make(configuration: AppConfiguration, schema: TelemetrySchema,
                            purchases: any PurchaseProviding = MockPurchases(),
                            defaults: UserDefaults = .standard, redaction: RedactionPolicy = .init()) -> AppServices {
        let logger = PulseLogger(redaction: redaction)
        let engine = LocalTelemetryEngine(logger: logger)
        return AppServices(configuration: configuration,
                           telemetry: Telemetry(configuration: configuration, schema: schema,
                                                analytics: [engine], diagnostics: [engine], redaction: redaction),
                           logger: logger, purchases: purchases,
                           developerOptions: DeveloperOptions(configuration: configuration, defaults: defaults))
    }
}
