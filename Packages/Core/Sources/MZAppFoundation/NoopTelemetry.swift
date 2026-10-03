/// Optional providers can be absent entirely, or represented explicitly by these inert engines.
@MainActor public final class NoopAnalyticsEngine: AnalyticsEngine {
    public let delivery = DeliveryKind.local
    public init() {}
    public func setEnabled(_ enabled: Bool) {}
    public func record(_ event: TelemetryEvent) -> EngineResult { .ignored }
}

@MainActor public final class NoopDiagnosticsEngine: DiagnosticsEngine {
    public let delivery = DeliveryKind.local
    public init() {}
    public func setEnabled(_ enabled: Bool) {}
    public func record(_ issue: DiagnosticIssue) -> EngineResult { .ignored }
    public func breadcrumb(_ event: TelemetryEvent) {}
}
