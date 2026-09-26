import Foundation
import Observation

public enum DeliveryKind: Sendable { case local, remote }
public enum EngineResult: Sendable { case recorded, ignored, failed }

@MainActor public protocol AnalyticsTracking: AnyObject {
    func track(_ event: any AnalyticsEvent)
}

@MainActor public protocol AnalyticsEngine: AnyObject {
    var delivery: DeliveryKind { get }
    func setEnabled(_ enabled: Bool)
    func record(_ event: TelemetryEvent) -> EngineResult
}

public struct DiagnosticIssue: Equatable, Sendable {
    public let code: String
    public let category: String
    public let metadata: [String: TelemetryValue]
    public let error: ErrorSnapshot?
    public let source: LogSource
    public init(code: String, category: String, metadata: [String: TelemetryValue] = [:],
                error: ErrorSnapshot? = nil, source: LogSource? = nil,
                file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.code = code
        self.category = category
        self.metadata = metadata
        self.error = error
        self.source = source ?? LogSource(file: file, function: function, line: line)
    }
}

@MainActor public protocol DiagnosticsReporting: AnyObject {
    func record(_ issue: DiagnosticIssue)
    func breadcrumb(_ event: any AnalyticsEvent)
}

@MainActor public protocol DiagnosticsEngine: AnyObject {
    var delivery: DeliveryKind { get }
    func setEnabled(_ enabled: Bool)
    func record(_ issue: DiagnosticIssue) -> EngineResult
    func breadcrumb(_ event: TelemetryEvent)
}

@MainActor @Observable public final class Telemetry: AnalyticsTracking, DiagnosticsReporting {
    public private(set) var preferences: DeliveryPreferences
    private let remoteAllowed: Bool
    private let analytics: [any AnalyticsEngine]
    private let diagnostics: [any DiagnosticsEngine]
    private let schema: TelemetrySchema
    private let redaction: RedactionPolicy

    public init(configuration: AppConfiguration, schema: TelemetrySchema,
                analytics: [any AnalyticsEngine] = [], diagnostics: [any DiagnosticsEngine] = [],
                redaction: RedactionPolicy = .init()) {
        self.preferences = configuration.preferences
        self.remoteAllowed = RuntimeSafety.permitsRemote(environment: configuration.environment)
        self.analytics = analytics
        self.diagnostics = diagnostics
        self.schema = schema
        self.redaction = redaction
        updatePreferences(configuration.preferences)
    }
    public func updatePreferences(_ preferences: DeliveryPreferences) {
        self.preferences = preferences
        for engine in analytics { engine.setEnabled(engine.delivery == .local || (remoteAllowed && preferences.analytics)) }
        for engine in diagnostics { engine.setEnabled(engine.delivery == .local || (remoteAllowed && preferences.diagnostics)) }
    }
    public func track(_ event: any AnalyticsEvent) {
        guard let event = schema.validate(event) else { return }
        for engine in analytics where engine.delivery == .local || (remoteAllowed && preferences.analytics) {
            _ = engine.record(event)
        }
    }
    public func record(_ issue: DiagnosticIssue) {
        let safe = DiagnosticIssue(code: issue.code, category: issue.category, metadata: redaction.sanitize(issue.metadata),
                                   error: issue.error, source: issue.source)
        for engine in diagnostics where engine.delivery == .local || (remoteAllowed && preferences.diagnostics) {
            _ = engine.record(safe)
        }
    }
    public func breadcrumb(_ event: any AnalyticsEvent) {
        guard let event = schema.validate(event) else { return }
        for engine in diagnostics where engine.delivery == .local || (remoteAllowed && preferences.diagnostics) {
            engine.breadcrumb(event)
        }
    }
}

@MainActor public final class RecordingAnalyticsEngine: AnalyticsEngine {
    public let delivery: DeliveryKind
    public private(set) var enabled = false
    public private(set) var events: [TelemetryEvent] = []
    public var result: EngineResult = .recorded
    public init(delivery: DeliveryKind = .local) { self.delivery = delivery }
    public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    public func record(_ event: TelemetryEvent) -> EngineResult {
        guard enabled else { return .ignored }
        events.append(event)
        return result
    }
    public func reset() { events.removeAll() }
}

@MainActor public final class RecordingDiagnosticsEngine: DiagnosticsEngine {
    public let delivery: DeliveryKind
    public private(set) var enabled = false
    public private(set) var issues: [DiagnosticIssue] = []
    public private(set) var breadcrumbs: [TelemetryEvent] = []
    public init(delivery: DeliveryKind = .local) { self.delivery = delivery }
    public func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    public func record(_ issue: DiagnosticIssue) -> EngineResult {
        guard enabled else { return .ignored }
        issues.append(issue)
        return .recorded
    }
    public func breadcrumb(_ event: TelemetryEvent) { if enabled { breadcrumbs.append(event) } }
}
