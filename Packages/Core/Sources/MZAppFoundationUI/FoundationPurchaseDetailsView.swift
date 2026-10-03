import MZAppFoundation
import SwiftUI

struct FoundationPurchaseDetailsView: View {
    let snapshot: PurchaseDiagnosticsSnapshot
    var body: some View {
        Section("Customer information freshness") {
            DiagnosticValueRow("Verification", value: snapshot.verification.rawValue)
            DiagnosticValueRow("Provider request date", value: snapshot.requestDate?.formatted() ?? "Not received")
            DiagnosticValueRow("Received in this session", value: snapshot.lastReceivedAt?.formatted() ?? "Not received")
            DiagnosticValueRow("Offerings received", value: snapshot.lastOfferingsFetchAt?.formatted() ?? "Not fetched")
            Text(snapshot.explanation).font(.caption).foregroundStyle(.secondary)
        }
        Section("Entitlements") {
            if snapshot.entitlements.isEmpty { Text("No cached entitlements") }
            ForEach(snapshot.entitlements) { entitlement in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entitlement.entitlementID).font(.headline)
                    DiagnosticValueRow("Product", value: entitlement.productID)
                    DiagnosticValueRow("Access", value: entitlement.isActive ? "Active" : "Inactive")
                    DiagnosticValueRow("Environment", value: entitlement.isSandbox.map { $0 ? "Sandbox" : "Production" } ?? "Unknown")
                    DiagnosticValueRow("Verification", value: entitlement.verification.rawValue)
                    if let expiry = entitlement.expiresAt { DiagnosticValueRow("Expires", value: expiry.formatted()) }
                }
            }
        }
        Section("Offerings") {
            if snapshot.offerings.isEmpty { Text("No cached offerings") }
            ForEach(snapshot.offerings) { offering in
                VStack(alignment: .leading, spacing: 4) {
                    Text(offering.offeringID + (offering.isCurrent ? " · Current" : "")).font(.headline)
                    DiagnosticValueRow("Products", value: offering.productIDs.joined(separator: ", "))
                    DiagnosticValueRow("Packages", value: offering.packageIDs.joined(separator: ", "))
                }
            }
        }
    }
}
