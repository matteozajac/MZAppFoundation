import Foundation
import MZAppFoundation
import RevenueCat

@MainActor final class RevenueCatPurchases: PurchaseProviding {
    private let sdk: Purchases
    private var packages: [String: RevenueCat.Package] = [:]
    private var revision = 0
    private var identityChanging = false
    private var monitor: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<EntitlementState>.Continuation] = [:]
    private let ledger = EntitlementLedger()
    var cachedState: EntitlementState? { ledger.state }

    init(key: String) throws {
        guard key.hasPrefix("appl_"), key.count > 10 else { throw BootstrapFailure.invalidRevenueCatKey }
        guard !Purchases.isConfigured else { throw BootstrapFailure.configurationConflict }
        sdk = Purchases.configure(with: Configuration.Builder(withAPIKey: key).with(entitlementVerificationMode: .informational))
        if let state = sdk.cachedCustomerInfo.map(Self.state) { ledger.receive(state) }
        let sdk = sdk
        monitor = Task { @MainActor [weak self] in
            for await info in sdk.customerInfoStream {
                guard let self, !Task.isCancelled else { return }
                if !self.identityChanging { self.publish(Self.state(info)) }
            }
        }
    }
    func updates() -> AsyncStream<EntitlementState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: EntitlementState.self, bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        if let cachedState { continuation.yield(cachedState) }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers.removeValue(forKey: id) }
        }
        return stream
    }
    func offers(offeringID: String?) async throws -> [PurchaseOffer] {
        let revision = try currentRevision()
        let offerings = try await perform { try await sdk.offerings() }
        try check(revision)
        let offering = offeringID.flatMap { offerings.all[$0] } ?? (offeringID == nil ? offerings.current : nil)
        guard let offering else { return [] }
        return offering.availablePackages.map { package in
            let id = offering.identifier + "/" + package.identifier
            packages[id] = package
            return PurchaseOffer(id: id, offeringID: offering.identifier, productID: package.storeProduct.productIdentifier,
                                 title: package.storeProduct.localizedTitle, localizedPrice: package.localizedPriceString)
        }
    }
    func refresh() async throws -> EntitlementState {
        let revision = try currentRevision()
        let ticket = ledger.beginRequest()
        let info = try await perform { try await sdk.customerInfo() }
        try check(revision)
        return accept(info, ticket: ticket)
    }
    func purchase(_ offer: PurchaseOffer) async throws -> PurchaseOutcome {
        let revision = try currentRevision()
        guard let package = packages[offer.id], package.storeProduct.productIdentifier == offer.productID else {
            throw PurchaseFailure.offerUnavailable
        }
        do {
            let result = try await sdk.purchase(package: package)
            try check(revision)
            if result.userCancelled { return .cancelled }
            let state = Self.state(result.customerInfo); publish(state); return .purchased(state)
        } catch {
            try check(revision)
            switch (error as NSError).code {
            case ErrorCode.purchaseCancelledError.rawValue: return .cancelled
            case ErrorCode.paymentPendingError.rawValue: return .pending
            case ErrorCode.networkError.rawValue: throw PurchaseFailure.network
            default: throw PurchaseFailure.failed
            }
        }
    }
    func restore() async throws -> EntitlementState {
        let revision = try currentRevision()
        let ticket = ledger.beginRequest()
        let info = try await perform { try await sdk.restorePurchases() }
        try check(revision)
        return accept(info, ticket: ticket)
    }
    func identify(_ userID: String?) async throws -> EntitlementState {
        guard !identityChanging else { throw PurchaseFailure.identityChanged }
        identityChanging = true
        revision += 1
        packages.removeAll()
        publish(.init())
        defer { identityChanging = false }
        let info: CustomerInfo
        if let userID {
            guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PurchaseFailure.failed }
            info = try await perform { try await sdk.logIn(userID).customerInfo }
        } else if sdk.isAnonymous { info = try await perform { try await sdk.customerInfo() } }
        else { info = try await perform { try await sdk.logOut() } }
        let state = Self.state(info); publish(state); return state
    }
    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch { throw (error as NSError).code == ErrorCode.networkError.rawValue ? PurchaseFailure.network : PurchaseFailure.failed }
    }
    private func currentRevision() throws -> Int {
        guard !identityChanging else { throw PurchaseFailure.identityChanged }
        return revision
    }
    private func check(_ expected: Int) throws {
        guard expected == revision, !identityChanging else { throw PurchaseFailure.identityChanged }
    }
    private func accept(_ info: CustomerInfo, ticket: UInt64) -> EntitlementState {
        let state = Self.state(info)
        if ledger.apply(state, ticket: ticket) {
            for continuation in subscribers.values { continuation.yield(state) }
        }
        return ledger.state ?? state
    }
    private func publish(_ state: EntitlementState) {
        ledger.receive(state)
        for continuation in subscribers.values { continuation.yield(state) }
    }
    private static func state(_ info: CustomerInfo) -> EntitlementState {
        EntitlementState(active: Set(info.entitlements.active.keys), verificationFailed: info.entitlements.verification == .failed)
    }
    deinit {
        monitor?.cancel()
        for continuation in subscribers.values { continuation.finish() }
    }
}
