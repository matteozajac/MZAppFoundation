import Foundation
import Testing
import MZAppFoundation
@testable import MZAppFoundationReporting

struct ReportDiagnosticsTests {
    @MainActor @Test func foundationSnapshotPassesReportingValidationWithoutChangingAccessOrPreferences() throws {
        let suite = "report-diagnostics-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = AppConfiguration(bundleIdentifier: "test.foundation", urlScheme: "test", environment: .local)
        let services = AppServices.testing(configuration: configuration,
            schema: TelemetrySchema(events: ["technical_event": ["attempt"]]), defaults: defaults)
        services.telemetry.track(TelemetryEvent("technical_event", properties: ["attempt": .integer(1), "user_id": .string("private-person")]))
        let enabled = services.developerOptions.isEnabled
        let snapshot = try services.diagnosticExport().jsonData()
        #expect(try ReportDiagnosticsAttachment.validated(snapshot) == snapshot)
        #expect(!String(decoding: snapshot, as: UTF8.self).contains("private-person"))
        #expect(services.developerOptions.isEnabled == enabled)
        #expect(services.telemetry.preferences == configuration.preferences)
    }

    @Test func diagnosticsIntakeRejectsSecretsMalformedUnboundedAndUnsupportedSnapshots() throws {
        let good = Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":1,"providers":[{"projectID":"proj_fixture"}]}"#.utf8)
        #expect(try ReportDiagnosticsAttachment.validated(good) == good)
        let invalid: [Data] = [
            Data("not JSON".utf8),
            Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":2}"#.utf8),
            Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":true}"#.utf8),
            Data(#"{"format":"other","schemaVersion":1}"#.utf8),
            Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":1,"apiKey":"private"}"#.utf8),
            Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":1,"user_id":"private"}"#.utf8),
            Data(repeating: 32, count: ReportDiagnosticsAttachment.maximumBytes + 1)
        ]
        for data in invalid {
            #expect(throws: ReportDiagnosticsAttachment.ValidationError.self) { try ReportDiagnosticsAttachment.validated(data) }
        }
    }

    @MainActor @Test func captureStoresOneSnapshotAndUsesSafeUnavailableState() throws {
        var calls = 0
        let capture = ReportDiagnosticsCapture.capture {
            calls += 1
            return Data(#"{"format":"mzappfoundation-diagnostics","schemaVersion":1}"#.utf8)
        }
        #expect(calls == 1)
        if case .available(let data) = capture { #expect(!data.isEmpty) } else { Issue.record("Expected snapshot") }
        let invalid = ReportDiagnosticsCapture.capture { Data("private failed output".utf8) }
        if case .unavailable = invalid {} else { Issue.record("Expected safe unavailable status") }
        let absent = ReportDiagnosticsCapture.capture(nil)
        if case .notProvided = absent {} else { Issue.record("Expected compatibility default") }
    }
}
