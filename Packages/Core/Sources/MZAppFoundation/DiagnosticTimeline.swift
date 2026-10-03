import Foundation
import Observation

/// Closed vocabularies prevent the timeline from becoming another store of log payloads.
public enum DiagnosticTimelineCategory: String, Codable, Sendable {
    case startup, developerOptions, analytics, diagnostics, breadcrumbs, preferences
    case provider, verification, mockScenario, runtime
}

public enum DiagnosticTimelineEvent: String, Codable, Sendable {
    case startup, providerStartup, preferencesChanged, schemaRejected, propertiesFiltered
    case runtimeBlocked, preferenceBlocked, adapterRecorded, adapterIgnored, adapterFailed
    case breadcrumbSubmitted, developerAccessChanged, developerAccessExpired, developerLinkRejected
    case diagnosticsExported, countersReset, mockScenarioChanged
    case verificationRequested, verificationSubmitted, verificationConfirmed, verificationUnavailable, verificationFailed
}

public enum DiagnosticTimelineStatus: String, Codable, Sendable {
    case recorded, submitted, ignored, failed, blocked, rejected, updated, enabled, disabled
}

public struct DiagnosticTimelineEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: DiagnosticTimelineCategory
    public let event: DiagnosticTimelineEvent
    public let status: DiagnosticTimelineStatus
    public let provider: FoundationProvider?

    public init(id: UUID = UUID(), timestamp: Date = Date(), category: DiagnosticTimelineCategory,
                event: DiagnosticTimelineEvent, status: DiagnosticTimelineStatus,
                provider: FoundationProvider? = nil) {
        self.id = id; self.timestamp = timestamp; self.category = category
        self.event = event; self.status = status; self.provider = provider
    }
}

/// Process-local, bounded history. It has no persistence or remote delivery of its own.
@MainActor @Observable public final class DiagnosticTimeline {
    public private(set) var entries: [DiagnosticTimelineEntry] = []
    public private(set) var discardedEntries = 0
    public let capacity: Int

    public init(capacity: Int = 200) { self.capacity = min(1_000, max(1, capacity)) }

    public func record(_ event: DiagnosticTimelineEvent, category: DiagnosticTimelineCategory,
                       status: DiagnosticTimelineStatus, provider: FoundationProvider? = nil) {
        entries.append(.init(category: category, event: event, status: status, provider: provider))
        if entries.count > capacity {
            let removed = entries.count - capacity
            entries.removeFirst(removed)
            discardedEntries += removed
        }
    }

    public func clear() {
        entries.removeAll(keepingCapacity: true)
        discardedEntries = 0
    }
}
