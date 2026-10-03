import XCTest
import MZAppFoundation
import MZAppFoundationFirebase
import MZAppFoundationLocal
import RevenueCat
@testable import MZAppFoundationLive

@MainActor final class ProviderAdapterDiagnosticsTests: XCTestCase {
    func testSuppressedLiveCompositionRetainsConfiguredAndInvalidEvidence() {
        let configuration = AppConfiguration(bundleIdentifier: "com.example.providers", urlScheme: "example", environment: .local)
        let vendors = LiveConfiguration(revenueCatPublicKey: "appl_example_public_key", sentryDSN: "invalid-private-dsn",
            revenueCatProject: .init(name: "Example project", projectID: "projExample"))
        let services = LiveServices.makeRecovering(configuration: configuration, vendors: vendors, schema: .init(events: [:]))
        let snapshots = services.providerSnapshots
        XCTAssertEqual(snapshots[1].configuration, .configured)
        XCTAssertEqual(snapshots[1].runtime, .suppressed)
        XCTAssertEqual(snapshots[1].delivery, .runtimeBlocked)
        XCTAssertTrue(snapshots[1].details.contains { $0.value == "Example project" })
        XCTAssertEqual(snapshots[2].configuration, .invalid)
        XCTAssertFalse(String(reflecting: snapshots).contains("invalid-private-dsn"))
        XCTAssertFalse(String(reflecting: snapshots).contains("appl_example_public_key"))
    }

    func testFirebaseMissingAndValidFilesRemainInspectableWithoutInitialization() throws {
        let configuration = AppConfiguration(bundleIdentifier: "com.example.providers", urlScheme: "example", environment: .local)
        let missing = FirebaseServices.makeRecovering(configuration: configuration, vendors: .init(),
            schema: .init(events: [:]), googleServiceInfoPath: nil).providerSnapshots[0]
        XCTAssertEqual(missing.configuration, .missing)
        XCTAssertEqual(missing.runtime, .notInitialized)
        XCTAssertNotNil(missing.sdkVersion)

        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: path) }
        let plist = ["PROJECT_ID": "example-project", "GOOGLE_APP_ID": "1:123:ios:abc", "GCM_SENDER_ID": "123",
                     "BUNDLE_ID": configuration.bundleIdentifier, "API_KEY": "hidden-client-key"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: path)
        let configured = FirebaseServices.makeRecovering(configuration: configuration, vendors: .init(),
            schema: .init(events: [:]), googleServiceInfoPath: path.path, firebaseProjectName: "Example Firebase project").providerSnapshots[0]
        XCTAssertEqual(configured.configuration, .configured)
        XCTAssertEqual(configured.runtime, .suppressed)
        XCTAssertEqual(configured.delivery, .runtimeBlocked)
        XCTAssertTrue(configured.details.contains { $0.value == "Example Firebase project" })
        XCTAssertEqual(configured.identityAudit.supplied?.projectID, "example-project")
        XCTAssertEqual(configured.identityAudit.supplied?.appID, "1:123:ios:abc")
        XCTAssertEqual(configured.identityAudit.ownership, .notInitialized)
        XCTAssertFalse(String(reflecting: configured).contains("hidden-client-key"))

        let fallback = FirebaseServices.diagnostics(googleServiceInfoPath: path.path, bootstrapFailure: true)
            .snapshots(configuration: configuration, preferences: .init())[0]
        XCTAssertEqual(fallback.configuration, .configured)
        XCTAssertEqual(fallback.runtime, .failed)
        XCTAssertEqual(fallback.delivery, .unavailable)
    }

    func testStartupValidationIdentifiesEachFailureWithoutSecrets() throws {
        let vendors = LiveConfiguration(revenueCatPublicKey: "private-invalid-key", sentryDSN: "private-invalid-dsn")
        let records = LiveServices.configurationRecords(vendors: vendors)
        XCTAssertEqual(records.filter { $0.status == .failed }.map(\.provider), [.revenueCat, .sentry])
        let recovery = LiveServices.recoveryRecords(for: ProviderBootstrapError(records: records))
        XCTAssertEqual(recovery.last?.stage, .recovery)
        XCTAssertEqual(recovery.last?.status, .succeeded)
        let exported = String(decoding: try JSONEncoder().encode(recovery), as: UTF8.self)
        XCTAssertFalse(exported.contains("private-invalid"))
        XCTAssertTrue(records.allSatisfy { $0.correction != nil })
    }

    func testIdentityAuditComparesKnownIdentifiersAndKeepsUnknownSeparate() {
        let unknown = ProviderIdentityAudit(expected: .init(projectID: "expected"), supplied: .init(),
            ownership: .notInitialized)
        XCTAssertFalse(unknown.findings.contains { $0.code.contains("mismatch") })
        let mismatch = ProviderIdentityAudit(expected: .init(projectID: "expected"),
            supplied: .init(projectID: "supplied"), running: .init(projectID: "running"), ownership: .external)
        XCTAssertEqual(mismatch.findings.filter { $0.code.contains("mismatch") }.count, 3)
        XCTAssertTrue(mismatch.findings.contains { $0.code == "identity.external_initializer" })
        XCTAssertEqual(SentryProvider.identity(fromDSN: "https://private-key@ingest.example.com/1234")?.projectID, "1234")
        XCTAssertNil(SentryProvider.identity(fromDSN: "https://private-key@ingest.example.com/1234?private=true"))
        XCTAssertFalse(SentryProvider.isValidDSN("https://private-key@ingest.example.com/not-a-project"))
        XCTAssertFalse(SentryProvider.isValidDSN("https://private-key@ingest.example.com/١٢٣"))
        let sentry = SentryProvider.diagnostics(dsn: "https://private-key@ingest.example.com/1234",
            project: .init(projectID: "9999")).snapshots(
                configuration: .init(bundleIdentifier: "com.example.audit", urlScheme: "audit", environment: .local),
                preferences: .init())[2]
        XCTAssertTrue(sentry.findings.contains { $0.code == "identity.sentry.declared_dsn_project_mismatch" })
    }

    func testManualSentryVerificationHonorsCurrentRuntimeAndPreferences() async throws {
        let configuration = AppConfiguration(bundleIdentifier: "com.example.verification", urlScheme: "verification", environment: .local)
        let engine = try SentryDiagnostics(dsn: "https://private-key@ingest.example.com/1234", configuration: configuration)
        let inventory = SentryProvider.diagnostics(dsn: "https://private-key@ingest.example.com/1234", engine: engine)
        let services = MZAppFoundationLocal.LocalServices.make(configuration: configuration, schema: .init(events: [:]),
            foundationDiagnostics: inventory, additionalDiagnostics: [engine])
        let action = try XCTUnwrap(inventory.actions.first)
        let result = await action.perform(context: services.providerInspectionContext)
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(services.providerSnapshots[2].identityAudit.ownership, .notInitialized)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(services.providerSnapshots), as: UTF8.self).contains("private-key"))
    }

    func testPurchaseDiagnosticsKeepsPerEntitlementEnvironmentAndRedactsIdentity() throws {
        let body = """
        {"request_date":"2026-10-03T10:00:00Z", "entitlement_verification":2,
         "subscriber":{"first_seen":"2026-10-03T10:00:00Z", "original_app_user_id":"private-customer-identifier",
         "subscriptions":{
           "app.sandbox":{"purchase_date":"2026-10-01T10:00:00Z","expires_date":"2027-10-01T10:00:00Z","store":"app_store","is_sandbox":true},
           "app.production":{"purchase_date":"2026-10-01T10:00:00Z","expires_date":"2027-10-01T10:00:00Z","store":"app_store","is_sandbox":false}},
         "entitlements":{
           "sandbox":{"product_identifier":"app.sandbox","purchase_date":"2026-10-01T10:00:00Z","expires_date":"2027-10-01T10:00:00Z"},
           "production":{"product_identifier":"app.production","purchase_date":"2026-10-01T10:00:00Z","expires_date":"2027-10-01T10:00:00Z"}}}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let info = try decoder.decode(CustomerInfo.self, from: Data(body.utf8))
        let snapshot = RevenueCatPurchases.diagnostics(for: info)
        XCTAssertEqual(snapshot.entitlements.count, 2)
        XCTAssertEqual(snapshot.entitlements.first { $0.entitlementID == "sandbox" }?.isSandbox, true)
        XCTAssertEqual(snapshot.entitlements.first { $0.entitlementID == "production" }?.isSandbox, false)
        XCTAssertEqual(snapshot.verification, .failed)
        XCTAssertNotNil(snapshot.requestDate)
        let export = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(export.contains("private-customer-identifier"))
        XCTAssertFalse(export.contains("transaction"))
    }
}
