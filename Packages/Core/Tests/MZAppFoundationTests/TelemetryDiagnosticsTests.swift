import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct TelemetryDiagnosticsTests {
    private let configuration = AppConfiguration(bundleIdentifier: "test.foundation", urlScheme: "test",
                                                   environment: .local, version: "1.2", build: "8")
    private let schema = TelemetrySchema(events: ["accepted": ["count", "long", "number", "token"]])

    @Test func rejectedEventsAndFilteredPropertiesAreCountedWithoutPayloadHistory() throws {
        let recorded = RecordingAnalyticsEngine()
        let ignored = RecordingAnalyticsEngine(); ignored.result = .ignored
        let failed = RecordingAnalyticsEngine(); failed.result = .failed
        let telemetry = Telemetry(configuration: configuration, schema: schema, analytics: [recorded, ignored, failed])
        telemetry.track(TelemetryEvent("private email@example.test", properties: ["user_id": .string("private-customer")]))
        telemetry.track(TelemetryEvent("accepted", properties: ["count": .integer(3), "token": .string("private-token"),
            "long": .string(String(repeating: "x", count: 101)), "number": .double(.infinity)]))
        #expect(telemetry.counters.analytics.attempts == 2)
        #expect(telemetry.counters.analytics.schemaRejected == 1)
        #expect(telemetry.counters.analytics.filteredProperties == 3)
        #expect(telemetry.counters.analytics.recorded == 1)
        #expect(telemetry.counters.analytics.recordedLocal == 1)
        #expect(telemetry.counters.analytics.ignored == 1)
        #expect(telemetry.counters.analytics.failed == 1)
        #expect(recorded.events.first?.properties == ["count": .integer(3)])
        let history = String(decoding: try JSONEncoder().encode(telemetry.timeline.entries), as: UTF8.self)
        #expect(!history.contains("private"))
        #expect(!history.contains("accepted"))
        #expect(telemetry.timeline.entries.contains { $0.event == .schemaRejected })
        #expect(telemetry.timeline.entries.contains { $0.event == .adapterFailed })
    }

    @Test func localDeliveryContinuesWhileRemotePreferenceAndRuntimeBlocksAreVisible() {
        let local = RecordingAnalyticsEngine()
        let remote = RecordingAnalyticsEngine(delivery: .remote)
        let telemetry = Telemetry(configuration: configuration, schema: schema, analytics: [local, remote])
        telemetry.updatePreferences(.init(analytics: false, diagnostics: false))
        telemetry.track(TelemetryEvent("accepted"))
        #expect(local.events.count == 1)
        #expect(remote.events.isEmpty)
        #expect(telemetry.counters.analytics.preferenceBlocked == 1)
        #expect(telemetry.counters.analytics.runtimeBlocked == 1)
        #expect(telemetry.counters.analytics.submittedRemote == 0)
        #expect(telemetry.timeline.entries.contains { $0.event == .preferencesChanged })
    }

    @Test func diagnosticAndBreadcrumbCountersDistinguishAdapterAcceptanceFromSubmission() {
        let engine = RecordingDiagnosticsEngine()
        let telemetry = Telemetry(configuration: configuration, schema: schema, diagnostics: [engine])
        telemetry.record(.init(code: "private-issue-code", category: "private-category",
                               metadata: ["user_id": .string("private-person"), "attempt": .integer(1)]))
        telemetry.breadcrumb(TelemetryEvent("accepted", properties: ["token": .string("private-token")]))
        telemetry.breadcrumb(TelemetryEvent("not_allowed"))
        #expect(telemetry.counters.diagnostics.attempts == 1)
        #expect(telemetry.counters.diagnostics.filteredProperties == 1)
        #expect(telemetry.counters.diagnostics.recorded == 1)
        #expect(engine.issues.first?.metadata == ["attempt": .integer(1)])
        #expect(telemetry.counters.breadcrumbs.attempts == 2)
        #expect(telemetry.counters.breadcrumbs.filteredProperties == 1)
        #expect(telemetry.counters.breadcrumbs.schemaRejected == 1)
        #expect(telemetry.counters.breadcrumbs.submitted == 1)
        #expect(telemetry.counters.breadcrumbs.recorded == 0)
        #expect(engine.breadcrumbs.first?.properties.isEmpty == true)
        #expect(telemetry.timeline.entries.last?.event == .schemaRejected)
    }

    @Test func timelineIsBoundedAndResetDoesNotChangeDeliveryOrAccess() {
        let timeline = DiagnosticTimeline(capacity: 2)
        let telemetry = Telemetry(configuration: configuration, schema: schema, timeline: timeline)
        for _ in 0..<4 { timeline.record(.startup, category: .startup, status: .recorded) }
        #expect(timeline.entries.count == 2)
        #expect(timeline.discardedEntries == 2)
        telemetry.track(TelemetryEvent("accepted"))
        #expect(telemetry.counters.analytics.noEngines == 1)
        telemetry.resetCounters()
        #expect(telemetry.counters == TelemetryCounters())
        #expect(telemetry.preferences == configuration.preferences)
        #expect(timeline.entries.last?.event == .countersReset)
        timeline.clear()
        #expect(timeline.entries.isEmpty)
        #expect(timeline.discardedEntries == 0)
        #expect(DiagnosticTimeline(capacity: 100_000).capacity == 1_000)
    }

    @Test func diagnosticExportPreservesProjectEvidenceAndExcludesRawPrivateFields() throws {
        let suite = "foundation-export-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secret = "appl_private_fixture_do_not_export"
        let inventory = FoundationDiagnostics(inspections: [.revenueCat: { _ in
            ProviderSnapshot(provider: .revenueCat, sdkVersion: "5.88.0", configuration: .configured,
                details: [.init("projectName", label: secret, value: "My App Project"),
                          .init("projectID", label: "Project ID", value: "proj_123"),
                          .init("API_KEY", label: "API key", value: secret),
                          .init("raw", label: "Private", value: secret),
                          .init("key", label: "Key", value: secret)], explanation: secret,
                identityAudit: .init(expected: .init(name: "My App Project", projectID: "proj_123"),
                                     supplied: .init(projectID: "proj_123"), ownership: .ownedByComposition),
                findings: [.init(code: "identity.test", severity: .warning, message: secret, correction: secret)])
        }], bootstrapIssue: secret,
        startupRecords: [.init(provider: .revenueCat, stage: .validation, status: .failed,
                              code: "configuration.test", message: secret, correction: secret)],
        buildMetadata: .init(appRevision: "aabbcc123", foundationRevision: "ddeeff456", buildChannel: "Internal",
                             resolvedPackageVersions: ["purchases-ios": "5.88.0", "apiKey": secret],
                             appWorkingTreeModified: true, foundationWorkingTreeModified: false, provenance: secret),
        purchaseDiagnostics: { .init(entitlements: [.init(entitlementID: "premium", productID: "test.premium",
                                                         isActive: false, isSandbox: true, verification: .failed)], explanation: secret) },
        additionalInspections: [.init(id: "cloudkit") { _ in
            .init(id: "cloudkit", title: "CloudKit", summary: secret,
                  details: [.init("containerID", label: secret, value: "iCloud.test.foundation"),
                            .init("account", label: "Account", value: secret),
                            .init("userID", label: "User", value: "private-user")],
                  exportableDetailIDs: ["containerID", "userID"])
        }])
        let options = DeveloperOptions(configuration: configuration, defaults: defaults)
        let telemetry = Telemetry(configuration: configuration, schema: schema)
        let services = AppServices(configuration: configuration, telemetry: telemetry, logger: RecordingLogger(),
                                   purchases: MockPurchases(), developerOptions: options, foundationDiagnostics: inventory)
        let before = options.isEnabled
        let snapshot = services.diagnosticExport()
        let data = try snapshot.jsonData()
        let json = String(decoding: data, as: UTF8.self)
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.providers.first { $0.provider == .revenueCat }?.identityAudit.expected?.projectID == "proj_123")
        #expect(json.contains("My App Project"))
        #expect(json.contains("configuration.test"))
        #expect(json.contains("purchases-ios"))
        #expect(snapshot.additionalSections.first?.details == [.init("containerID", label: "containerID", value: "iCloud.test.foundation")])
        #expect(!json.contains(secret))
        #expect(!json.contains("API_KEY"))
        #expect(!json.contains("apiKey"))
        #expect(!snapshot.text.contains(secret))
        #expect(snapshot.text.contains("sandbox true"))
        #expect(snapshot.text.contains("App working tree modified: true"))
        #expect(snapshot.text.contains("Foundation working tree modified: false"))
        #expect(options.isEnabled == before)
        #expect(telemetry.preferences == configuration.preferences)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(FoundationDiagnosticExport.self, from: data)
        #expect(restored.providers == snapshot.providers)
        #expect(restored.counters == snapshot.counters)
        #expect(restored.app.bundleIdentifier == configuration.bundleIdentifier)
    }
}
