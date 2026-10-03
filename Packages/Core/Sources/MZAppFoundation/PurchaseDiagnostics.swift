import Foundation

public enum PurchaseVerificationState: String, Codable, Sendable {
    case notRequested, verified, verifiedOnDevice, failed, unknown
}

public struct PurchaseEntitlementDiagnostic: Equatable, Codable, Identifiable, Sendable {
    public var id: String { entitlementID }
    public let entitlementID: String
    public let productID: String
    public let isActive: Bool
    /// Environment belongs to each entitlement; one customer may own both sandbox and production purchases.
    public let isSandbox: Bool?
    public let verification: PurchaseVerificationState
    public let expiresAt: Date?
    public init(entitlementID: String, productID: String, isActive: Bool, isSandbox: Bool? = nil,
                verification: PurchaseVerificationState = .unknown, expiresAt: Date? = nil) {
        self.entitlementID = entitlementID; self.productID = productID; self.isActive = isActive
        self.isSandbox = isSandbox; self.verification = verification; self.expiresAt = expiresAt
    }
}

public struct PurchaseOfferingDiagnostic: Equatable, Codable, Identifiable, Sendable {
    public var id: String { offeringID }
    public let offeringID: String
    public let isCurrent: Bool
    public let productIDs: [String]
    public let packageIDs: [String]
    public init(offeringID: String, isCurrent: Bool, productIDs: [String], packageIDs: [String]) {
        self.offeringID = offeringID; self.isCurrent = isCurrent
        self.productIDs = productIDs; self.packageIDs = packageIDs
    }
}

/// Passive cached diagnostics. No user identity, receipt, token, transaction ID, or purchase authorization.
public struct PurchaseDiagnosticsSnapshot: Equatable, Codable, Sendable {
    public let provider: FoundationProvider
    public let entitlements: [PurchaseEntitlementDiagnostic]
    public let offerings: [PurchaseOfferingDiagnostic]
    public let verification: PurchaseVerificationState
    public let requestDate: Date?
    public let lastReceivedAt: Date?
    public let lastOfferingsFetchAt: Date?
    public let explanation: String
    public init(provider: FoundationProvider = .revenueCat, entitlements: [PurchaseEntitlementDiagnostic] = [],
                offerings: [PurchaseOfferingDiagnostic] = [], verification: PurchaseVerificationState = .unknown,
                requestDate: Date? = nil, lastReceivedAt: Date? = nil, lastOfferingsFetchAt: Date? = nil,
                explanation: String = "Customer information and offerings have not been received in this session.") {
        self.provider = provider; self.entitlements = entitlements; self.offerings = offerings
        self.verification = verification; self.requestDate = requestDate; self.lastReceivedAt = lastReceivedAt
        self.lastOfferingsFetchAt = lastOfferingsFetchAt; self.explanation = explanation
    }
}
