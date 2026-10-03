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
    public private(set) var counters = TelemetryCounters()
    public let timeline: DiagnosticTimeline
    private let remoteAllowed: Bool
    private let analytics: [any AnalyticsEngine]
    private let diagnostics: [any DiagnosticsEngine]
    private let schema: TelemetrySchema
    private let redaction: RedactionPolicy

    public init(configuration: AppConfiguration, schema: TelemetrySchema,
                analytics: [any AnalyticsEngine] = [], diagnostics: [any DiagnosticsEngine] = [],
                redaction: RedactionPolicy = .init(), timeline: DiagnosticTimeline = .init()) {
        self.preferences = configuration.preferences
        self.remoteAllowed = RuntimeSafety.permitsRemote(environment: configuration.environment)
        self.analytics = analytics
        self.diagnostics = diagnostics
        self.schema = schema
        self.redaction = redaction
        self.timeline = timeline
        updatePreferences(configuration.preferences)
    }
    public func updatePreferences(_ preferences: DeliveryPreferences) {
        let changed = self.preferences != preferences
        self.preferences = preferences
        for engine in analytics { engine.setEnabled(engine.delivery == .local || (remoteAllowed && preferences.analytics)) }
        for engine in diagnostics { engine.setEnabled(engine.delivery == .local || (remoteAllowed && preferences.diagnostics)) }
        if changed { timeline.record(.preferencesChanged, category: .preferences, status: .updated) }
    }
    public func resetCounters() {
        counters = TelemetryCounters()
        timeline.record(.countersReset, category: .runtime, status: .updated)
    }
    public func track(_ event: any AnalyticsEvent) {
        counters.analytics.attempts += 1
        guard let safe = schema.validate(event) else {
            counters.analytics.schemaRejected += 1
            timeline.record(.schemaRejected, category: .analytics, status: .rejected)
            return
        }
        let filtered = event.properties.count - safe.properties.count
        counters.analytics.filteredProperties += filtered
        if filtered > 0 { timeline.record(.propertiesFiltered, category: .analytics, status: .updated) }
        if analytics.isEmpty { counters.analytics.noEngines += 1 }
        for engine in analytics {
            guard deliveryAllowed(engine.delivery, preference: preferences.analytics, category: .analytics,
                                  counters: &counters.analytics) else { continue }
            count(engine.record(safe), delivery: engine.delivery, category: .analytics, counters: &counters.analytics)
        }
    }
    public func record(_ issue: DiagnosticIssue) {
        counters.diagnostics.attempts += 1
        let safe = DiagnosticIssue(code: issue.code, category: issue.category, metadata: redaction.sanitize(issue.metadata),
                                   error: issue.error, source: issue.source)
        let filtered = issue.metadata.count - safe.metadata.count
        counters.diagnostics.filteredProperties += filtered
        if filtered > 0 { timeline.record(.propertiesFiltered, category: .diagnostics, status: .updated) }
        if diagnostics.isEmpty { counters.diagnostics.noEngines += 1 }
        for engine in diagnostics {
            guard deliveryAllowed(engine.delivery, preference: preferences.diagnostics, category: .diagnostics,
                                  counters: &counters.diagnostics) else { continue }
            count(engine.record(safe), delivery: engine.delivery, category: .diagnostics, counters: &counters.diagnostics)
        }
    }
    public func breadcrumb(_ event: any AnalyticsEvent) {
        counters.breadcrumbs.attempts += 1
        guard let safe = schema.validate(event) else {
            counters.breadcrumbs.schemaRejected += 1
            timeline.record(.schemaRejected, category: .breadcrumbs, status: .rejected)
            return
        }
        let filtered = event.properties.count - safe.properties.count
        counters.breadcrumbs.filteredProperties += filtered
        if filtered > 0 { timeline.record(.propertiesFiltered, category: .breadcrumbs, status: .updated) }
        if diagnostics.isEmpty { counters.breadcrumbs.noEngines += 1 }
        for engine in diagnostics {
            guard deliveryAllowed(engine.delivery, preference: preferences.diagnostics, category: .breadcrumbs,
                                  counters: &counters.breadcrumbs) else { continue }
            engine.breadcrumb(safe)
            // The existing breadcrumb protocol has no result; only a submission can be observed.
            counters.breadcrumbs.submitted += 1
            if engine.delivery == .remote { counters.breadcrumbs.submittedRemote += 1 }
            timeline.record(.breadcrumbSubmitted, category: .breadcrumbs, status: .submitted)
        }
    }

    private func deliveryAllowed(_ delivery: DeliveryKind, preference: Bool,
                                 category: DiagnosticTimelineCategory,
                                 counters: inout TelemetryChannelCounters) -> Bool {
        guard delivery == .remote else { return true }
        if !remoteAllowed {
            counters.runtimeBlocked += 1
            timeline.record(.runtimeBlocked, category: category, status: .blocked)
        }
        if !preference {
            counters.preferenceBlocked += 1
            timeline.record(.preferenceBlocked, category: category, status: .blocked)
        }
        return remoteAllowed && preference
    }

    private func count(_ result: EngineResult, delivery: DeliveryKind,
                       category: DiagnosticTimelineCategory, counters: inout TelemetryChannelCounters) {
        switch result {
        case .recorded:
            counters.recorded += 1
            if delivery == .local { counters.recordedLocal += 1 } else { counters.submittedRemote += 1 }
            timeline.record(.adapterRecorded, category: category, status: delivery == .local ? .recorded : .submitted)
        case .ignored:
            counters.ignored += 1
            timeline.record(.adapterIgnored, category: category, status: .ignored)
        case .failed:
            counters.failed += 1
            timeline.record(.adapterFailed, category: category, status: .failed)
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
