/// Orders entitlement responses so a delayed request cannot overwrite a newer request or push update.
@MainActor public final class EntitlementLedger {
    public private(set) var state: EntitlementState?
    private var revision: UInt64 = 0
    public init(state: EntitlementState? = nil) { self.state = state }

    public func beginRequest() -> UInt64 { revision &+= 1; return revision }
    @discardableResult public func apply(_ state: EntitlementState, ticket: UInt64) -> Bool {
        guard ticket == revision else { return false }
        self.state = state
        revision &+= 1
        return true
    }
    public func receive(_ state: EntitlementState) {
        revision &+= 1
        self.state = state
    }
}
