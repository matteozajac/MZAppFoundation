import Foundation

public enum ProviderVerificationStatus: String, Codable, Sendable {
    case submitted, confirmed, failed, unavailable
}

public struct ProviderVerificationResult: Equatable, Codable, Sendable {
    public let status: ProviderVerificationStatus
    public let code: String
    public let message: String
    public let reference: String?
    public let completedAt: Date
    public init(status: ProviderVerificationStatus, code: String, message: String, reference: String? = nil, completedAt: Date = .now) {
        self.status = status; self.code = code; self.message = message; self.completedAt = completedAt
        self.reference = reference
    }
}

@MainActor public struct ProviderVerificationAction: Identifiable {
    public let id: String
    public let title: String
    public let provider: FoundationProvider?
    private let operation: @MainActor (ProviderInspectionContext) async -> ProviderVerificationResult
    public init(id: String, title: String, provider: FoundationProvider? = nil,
                operation: @escaping @MainActor (ProviderInspectionContext) async -> ProviderVerificationResult) {
        self.id = id; self.title = title; self.provider = provider; self.operation = operation
    }
    public func perform(context: ProviderInspectionContext) async -> ProviderVerificationResult {
        await operation(context)
    }
}
