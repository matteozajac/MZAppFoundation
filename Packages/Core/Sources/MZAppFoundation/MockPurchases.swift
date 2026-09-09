import Foundation

@MainActor public final class MockPurchases: PurchaseProviding {
    public enum Call: Equatable, Sendable { case offers(String?), refresh, purchase(String), restore, identify(String?) }
    public private(set) var calls: [Call] = []
    public private(set) var cachedState: EntitlementState?
    public var availableOffers: [PurchaseOffer]
    public var purchaseResult: Result<PurchaseOutcome, PurchaseFailure> = .success(.cancelled)
    public var restoreResult: Result<EntitlementState, PurchaseFailure> = .success(.init())
    public var refreshResult: Result<EntitlementState, PurchaseFailure> = .success(.init())
    private var subscribers: [UUID: AsyncStream<EntitlementState>.Continuation] = [:]

    public init(offers: [PurchaseOffer] = [], state: EntitlementState = .init()) {
        availableOffers = offers; cachedState = state
    }
    public func updates() -> AsyncStream<EntitlementState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: EntitlementState.self, bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        if let cachedState { continuation.yield(cachedState) }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }
    public func send(_ state: EntitlementState) {
        cachedState = state
        for subscriber in subscribers.values { subscriber.yield(state) }
    }
    public func offers(offeringID: String?) async throws -> [PurchaseOffer] {
        calls.append(.offers(offeringID))
        return availableOffers.filter { offeringID == nil || $0.offeringID == offeringID }
    }
    public func refresh() async throws -> EntitlementState {
        calls.append(.refresh)
        let state = try refreshResult.get(); send(state); return state
    }
    public func purchase(_ offer: PurchaseOffer) async throws -> PurchaseOutcome {
        calls.append(.purchase(offer.id))
        guard availableOffers.contains(offer) else { throw PurchaseFailure.offerUnavailable }
        let result = try purchaseResult.get()
        if case .purchased(let state) = result { send(state) }
        return result
    }
    public func restore() async throws -> EntitlementState {
        calls.append(.restore)
        let state = try restoreResult.get(); send(state); return state
    }
    public func identify(_ userID: String?) async throws -> EntitlementState {
        calls.append(.identify(userID))
        let state = EntitlementState(); send(state); return state
    }
    public func finish() {
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers.removeAll()
    }
    deinit { for subscriber in subscribers.values { subscriber.finish() } }
}
