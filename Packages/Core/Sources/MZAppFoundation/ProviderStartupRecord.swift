import Foundation

public enum ProviderStartupStage: String, Codable, Sendable {
    case validation, initialization, recovery, runtimeSafety
}

public enum ProviderStartupStatus: String, Codable, Sendable {
    case succeeded, failed, skipped
}

public struct ProviderStartupRecord: Equatable, Codable, Identifiable, Sendable {
    public var id: String { (provider?.rawValue ?? "composition") + "." + stage.rawValue + "." + code }
    public let provider: FoundationProvider?
    public let stage: ProviderStartupStage
    public let status: ProviderStartupStatus
    public let code: String
    public let message: String
    public let correction: String?
    public let recordedAt: Date
    public init(provider: FoundationProvider? = nil, stage: ProviderStartupStage, status: ProviderStartupStatus,
                code: String, message: String, correction: String? = nil, recordedAt: Date = .now) {
        self.provider = provider; self.stage = stage; self.status = status
        self.code = code; self.message = message; self.correction = correction; self.recordedAt = recordedAt
    }
}

/// Carries only allowlisted records. Provider error payloads never enter developer exports.
public struct ProviderBootstrapError: Error, Sendable {
    public let records: [ProviderStartupRecord]
    public init(records: [ProviderStartupRecord]) { self.records = records }
}

public enum BootstrapFailure: Error, Sendable {
    case configurationConflict, invalidRevenueCatKey, invalidSentryDSN, invalidFirebaseConfiguration
}
