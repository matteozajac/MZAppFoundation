import Foundation

public struct PurchaseOffer: Equatable, Sendable, Identifiable {
    public let id: String
    public let offeringID: String
    public let productID: String
    public let title: String
    public let localizedPrice: String
    public init(id: String, offeringID: String, productID: String, title: String, localizedPrice: String) {
        self.id = id; self.offeringID = offeringID; self.productID = productID
        self.title = title; self.localizedPrice = localizedPrice
    }
}

public struct EntitlementState: Equatable, Sendable {
    public let active: Set<String>
    public let verificationFailed: Bool
    public init(active: Set<String> = [], verificationFailed: Bool = false) {
        self.active = verificationFailed ? [] : active
        self.verificationFailed = verificationFailed
    }
    public func hasAccess(to entitlement: String) -> Bool { active.contains(entitlement) }
}

public enum PurchaseOutcome: Equatable, Sendable {
    case purchased(EntitlementState), cancelled, pending
}
public enum PurchaseFailure: Error, Equatable, Sendable {
    case unavailable, offerUnavailable, network, failed, identityChanged
}

@MainActor public protocol PurchaseProviding: AnyObject {
    var cachedState: EntitlementState? { get }
    func updates() -> AsyncStream<EntitlementState>
    func offers(offeringID: String?) async throws -> [PurchaseOffer]
    func refresh() async throws -> EntitlementState
    func purchase(_ offer: PurchaseOffer) async throws -> PurchaseOutcome
    func restore() async throws -> EntitlementState
    func identify(_ userID: String?) async throws -> EntitlementState
}

@MainActor public final class UnavailablePurchases: PurchaseProviding {
    public init() {}
    public var cachedState: EntitlementState? { nil }
    public func updates() -> AsyncStream<EntitlementState> { AsyncStream { $0.finish() } }
    public func offers(offeringID: String?) async throws -> [PurchaseOffer] { throw PurchaseFailure.unavailable }
    public func refresh() async throws -> EntitlementState { throw PurchaseFailure.unavailable }
    public func purchase(_ offer: PurchaseOffer) async throws -> PurchaseOutcome { throw PurchaseFailure.unavailable }
    public func restore() async throws -> EntitlementState { throw PurchaseFailure.unavailable }
    public func identify(_ userID: String?) async throws -> EntitlementState { throw PurchaseFailure.unavailable }
}
