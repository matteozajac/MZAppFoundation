import Foundation

/// Counts calls and adapter outcomes without retaining event names, values, or user identities.
/// `recorded` means that an adapter accepted a record. It never proves backend receipt.
/// Attempts count public calls; delivery outcomes count adapters. Blocking reasons can overlap.
public struct TelemetryChannelCounters: Equatable, Codable, Sendable {
    public internal(set) var attempts = 0
    public internal(set) var schemaRejected = 0
    public internal(set) var filteredProperties = 0
    public internal(set) var preferenceBlocked = 0
    public internal(set) var runtimeBlocked = 0
    public internal(set) var noEngines = 0
    public internal(set) var recorded = 0
    public internal(set) var recordedLocal = 0
    public internal(set) var submittedRemote = 0
    public internal(set) var submitted = 0
    public internal(set) var ignored = 0
    public internal(set) var failed = 0

    public init() {}
}

public struct TelemetryCounters: Equatable, Codable, Sendable {
    public internal(set) var analytics = TelemetryChannelCounters()
    public internal(set) var diagnostics = TelemetryChannelCounters()
    public internal(set) var breadcrumbs = TelemetryChannelCounters()
    public init() {}
}
