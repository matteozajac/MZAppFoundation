import Foundation
import Observation
import MZAppFoundation
import RevenueCat

@MainActor @Observable public final class RevenueCatPurchases: PurchaseProviding {
    private static weak var owner: RevenueCatPurchases?
    private var diagnosticInfo: PurchaseDiagnosticsSnapshot?
    private var diagnosticOfferings: [PurchaseOfferingDiagnostic] = []
    private var lastReceivedAt: Date?
    private var lastOfferingsResponseAt: Date?
    private let sdk: Purchases
    private var packages: [String: RevenueCat.Package] = [:]
    private var revision = 0
    private var identityChanging = false
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<EntitlementState>.Continuation] = [:]
    private let ledger = EntitlementLedger()
    public var cachedState: EntitlementState? { ownsRunningSDK ? ledger.state : nil }
    public static var ownership: ProviderOwnership {
        guard Purchases.isConfigured else { return .notInitialized }
        return owner?.sdk === Purchases.shared ? .ownedByComposition : .external
    }
    public var ownsRunningSDK: Bool { Purchases.isConfigured && Self.owner === self && sdk === Purchases.shared }
    public var diagnosticsSnapshot: PurchaseDiagnosticsSnapshot {
        .init(entitlements: diagnosticInfo?.entitlements ?? [], offerings: diagnosticOfferings,
              verification: diagnosticInfo?.verification ?? .unknown, requestDate: diagnosticInfo?.requestDate,
              lastReceivedAt: lastReceivedAt, lastOfferingsFetchAt: lastOfferingsResponseAt,
              explanation: "Passive SDK responses only. Offerings can be cached; request date describes CustomerInfo freshness. Environment is recorded per entitlement. A manual refresh updates normal CustomerInfo state and follows the purchase provider's entitlement verification. This screen cannot override verification, perform purchases, or restore purchases.")
    }

    public func refreshDiagnostics() async -> ProviderVerificationResult {
        do {
            let revision = try currentRevision()
            let ticket = ledger.beginRequest()
            let info = try await perform { try await sdk.customerInfo(fetchPolicy: .fetchCurrent) }
            try check(revision)
            _ = accept(info, ticket: ticket)
            let offerings = try await perform { try await sdk.offerings() }
            try check(revision)
            receiveOfferings(offerings)
            return .init(status: .confirmed, code: "revenuecat.read_succeeded",
                message: "CustomerInfo and offerings were received from the SDK. Offerings may be cached; this does not verify a purchase or the App Store catalog.")
        } catch is CancellationError {
            return .init(status: .unavailable, code: "revenuecat.read_cancelled", message: "The diagnostic refresh was cancelled.")
        } catch {
            return .init(status: .failed, code: "revenuecat.read_failed",
                message: "The SDK could not refresh all purchase diagnostics. Any received data remains visible with its timestamp. Check connectivity and the app's RevenueCat configuration.")
        }
    }

    private func receiveDiagnostics(_ info: CustomerInfo) {
        lastReceivedAt = .now
        diagnosticInfo = Self.diagnostics(for: info)
    }

    public static func diagnostics(for info: CustomerInfo) -> PurchaseDiagnosticsSnapshot {
        .init(entitlements: info.entitlements.all.values.map { entitlement in
            PurchaseEntitlementDiagnostic(entitlementID: entitlement.identifier,
                productID: entitlement.productIdentifier, isActive: entitlement.isActive,
                isSandbox: entitlement.isSandbox, verification: verification(entitlement.verification),
                expiresAt: entitlement.expirationDate)
        }.sorted { $0.id < $1.id }, verification: verification(info.entitlements.verification), requestDate: info.requestDate)
    }

    private func receiveOfferings(_ offerings: Offerings) {
        diagnosticOfferings = offerings.all.values.map { offering in
            PurchaseOfferingDiagnostic(offeringID: offering.identifier,
                isCurrent: offerings.current?.identifier == offering.identifier,
                productIDs: offering.availablePackages.map { $0.storeProduct.productIdentifier }.sorted(),
                packageIDs: offering.availablePackages.map(\.identifier).sorted())
        }.sorted { $0.id < $1.id }
        lastOfferingsResponseAt = .now
    }

    private static func verification(_ value: VerificationResult) -> PurchaseVerificationState {
        switch value {
        case .notRequested: .notRequested
        case .verified: .verified
        case .verifiedOnDevice: .verifiedOnDevice
        case .failed: .failed
        @unknown default: .unknown
        }
    }

    public init(key: String, configuration: AppConfiguration) throws {
        guard RuntimeSafety.permitsRemote(environment: configuration.environment) else { throw PurchaseFailure.unavailable }
        guard key.hasPrefix("appl_"), key.count > 10 else { throw BootstrapFailure.invalidRevenueCatKey }
        guard !Purchases.isConfigured else { throw BootstrapFailure.configurationConflict }
        sdk = Purchases.configure(with: Configuration.Builder(withAPIKey: key).with(entitlementVerificationMode: .informational))
        Self.owner = self
        if let info = sdk.cachedCustomerInfo {
            ledger.receive(Self.state(info)); receiveDiagnostics(info)
        }
        let sdk = sdk
        monitor = Task { @MainActor [weak self] in
            for await info in sdk.customerInfoStream {
                guard let self, !Task.isCancelled else { return }
                if !self.identityChanging, self.ownsRunningSDK { self.receiveDiagnostics(info); self.publish(Self.state(info)) }
            }
        }
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
    public func offers(offeringID: String?) async throws -> [PurchaseOffer] {
        let revision = try currentRevision()
        let offerings = try await perform { try await sdk.offerings() }
        try check(revision)
        receiveOfferings(offerings)
        let offering = offeringID.flatMap { offerings.all[$0] } ?? (offeringID == nil ? offerings.current : nil)
        guard let offering else { return [] }
        return offering.availablePackages.map { package in
            let id = offering.identifier + "/" + package.identifier
            packages[id] = package
            return PurchaseOffer(id: id, offeringID: offering.identifier, productID: package.storeProduct.productIdentifier,
                                 title: package.storeProduct.localizedTitle, localizedPrice: package.localizedPriceString)
        }
    }
    public func refresh() async throws -> EntitlementState {
        let revision = try currentRevision()
        let ticket = ledger.beginRequest()
        let info = try await perform { try await sdk.customerInfo() }
        try check(revision)
        return accept(info, ticket: ticket)
    }
    public func purchase(_ offer: PurchaseOffer) async throws -> PurchaseOutcome {
        let revision = try currentRevision()
        guard let package = packages[offer.id], package.storeProduct.productIdentifier == offer.productID else {
            throw PurchaseFailure.offerUnavailable
        }
        do {
            let result = try await sdk.purchase(package: package)
            try check(revision)
            if result.userCancelled { return .cancelled }
            receiveDiagnostics(result.customerInfo)
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
    public func restore() async throws -> EntitlementState {
        let revision = try currentRevision()
        let ticket = ledger.beginRequest()
        let info = try await perform { try await sdk.restorePurchases() }
        try check(revision)
        return accept(info, ticket: ticket)
    }
    public func identify(_ userID: String?) async throws -> EntitlementState {
        guard !identityChanging, ownsRunningSDK else { throw PurchaseFailure.identityChanged }
        identityChanging = true
        revision += 1
        packages.removeAll()
        diagnosticInfo = nil; diagnosticOfferings = []; lastReceivedAt = nil; lastOfferingsResponseAt = nil
        publish(.init())
        defer { identityChanging = false }
        let info: CustomerInfo
        if let userID {
            guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PurchaseFailure.failed }
            info = try await perform { try await sdk.logIn(userID).customerInfo }
        } else if sdk.isAnonymous { info = try await perform { try await sdk.customerInfo() } }
        else { info = try await perform { try await sdk.logOut() } }
        guard ownsRunningSDK else { throw PurchaseFailure.identityChanged }
        receiveDiagnostics(info)
        let state = Self.state(info); publish(state); return state
    }
    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch { throw (error as NSError).code == ErrorCode.networkError.rawValue ? PurchaseFailure.network : PurchaseFailure.failed }
    }
    private func currentRevision() throws -> Int {
        guard !identityChanging, ownsRunningSDK else { throw PurchaseFailure.identityChanged }
        return revision
    }
    private func check(_ expected: Int) throws {
        guard expected == revision, !identityChanging, ownsRunningSDK else { throw PurchaseFailure.identityChanged }
    }
    private func accept(_ info: CustomerInfo, ticket: UInt64) -> EntitlementState {
        let state = Self.state(info)
        if ledger.apply(state, ticket: ticket) {
            receiveDiagnostics(info)
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
