import Foundation

public enum FoundationProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case firebase, revenueCat, sentry
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .firebase: "Firebase"
        case .revenueCat: "RevenueCat"
        case .sentry: "Sentry"
        }
    }
}

public enum ProviderConfigurationState: String, Codable, Sendable {
    case configured = "Configured"
    case notConfigured = "Not configured"
    case missing = "Missing configuration"
    case invalid = "Invalid configuration"
}

public enum ProviderRuntimeState: String, Codable, Sendable {
    case notLinked = "SDK not linked"
    case notInitialized = "Not initialized"
    case initialized = "Initialized"
    case suppressed = "Suppressed by runtime safety"
    case unsupported = "Unsupported on this platform"
    case failed = "Local fallback after bootstrap failure"
}

public enum ProviderDeliveryState: String, Codable, Sendable {
    case enabled = "Enabled"
    case preferenceDisabled = "Disabled by preference"
    case runtimeBlocked = "Blocked by runtime safety"
    case unavailable = "Unavailable"
    case notApplicable = "Not applicable"
}

/// Only allowlisted, non-secret configuration belongs here. Never pass keys, DSNs, or user IDs.
public struct ProviderDetail: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public init(_ id: String, label: String, value: String) {
        self.id = id; self.label = label; self.value = value
    }
}

public struct ProviderSnapshot: Equatable, Codable, Sendable, Identifiable {
    public let provider: FoundationProvider
    public var sdkVersion: String?
    public var versionSource: String?
    public var configuration: ProviderConfigurationState
    public var runtime: ProviderRuntimeState
    public var delivery: ProviderDeliveryState
    public var details: [ProviderDetail]
    public var explanation: String
    public var expectation: ProviderExpectation
    public var identityAudit: ProviderIdentityAudit
    public var findings: [DiagnosticFinding]
    public var id: FoundationProvider { provider }
    public var summary: String {
        if runtime == .notLinked {
            return configuration == .notConfigured ? "Not integrated" : runtime.rawValue + " · " + configuration.rawValue
        }
        if runtime == .unsupported || runtime == .failed { return runtime.rawValue }
        if configuration != .configured { return configuration.rawValue }
        if runtime == .suppressed { return runtime.rawValue }
        if delivery == .preferenceDisabled { return "Configured · delivery off" }
        return runtime.rawValue
    }

    public init(provider: FoundationProvider, sdkVersion: String? = nil, versionSource: String? = nil,
                configuration: ProviderConfigurationState = .notConfigured,
                runtime: ProviderRuntimeState = .notLinked, delivery: ProviderDeliveryState = .unavailable,
                details: [ProviderDetail] = [], explanation: String = "This provider is optional.",
                expectation: ProviderExpectation = .optional, identityAudit: ProviderIdentityAudit = .init(),
                findings: [DiagnosticFinding] = []) {
        self.provider = provider; self.sdkVersion = sdkVersion; self.versionSource = versionSource
        self.configuration = configuration; self.runtime = runtime; self.delivery = delivery
        self.details = details; self.explanation = explanation
        self.expectation = expectation; self.identityAudit = identityAudit; self.findings = findings
    }
}
