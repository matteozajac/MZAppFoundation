import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct ProviderRequirementsTests {
    private let configuration = AppConfiguration(bundleIdentifier: "com.example.required", urlScheme: "required", environment: .local)

    @Test func optionalAbsenceAndRequiredAbsenceHaveDifferentMeaning() {
        let optional = FoundationDiagnostics().snapshots(configuration: configuration, preferences: .init())
        #expect(optional.allSatisfy { $0.findings.allSatisfy { $0.severity == .info } })
        let required = FoundationDiagnostics(expectations: [.init(.firebase, expectation: .required)])
            .snapshots(configuration: configuration, preferences: .init())[0]
        #expect(required.expectation == .required)
        #expect(required.findings.contains { $0.code == "required_adapter" && $0.severity == .error })
        #expect(required.findings.contains { $0.code == "required_configuration" })
    }

    @Test func scopedRulesAllowPlatformAndEnvironmentExceptions() {
        let rules: [ProviderRequirement] = [.init(.firebase, expectation: .required),
            .init(.firebase, expectation: .intentionallyUnused, environments: [.local], platforms: [.current])]
        let inventory = FoundationDiagnostics(expectations: rules)
        #expect(inventory.snapshots(configuration: configuration, preferences: .init())[0].expectation == .intentionallyUnused)
        let production = AppConfiguration(bundleIdentifier: configuration.bundleIdentifier, urlScheme: "required", environment: .production)
        #expect(inventory.snapshots(configuration: production, preferences: .init())[0].expectation == .required)
        #expect(!ProviderRequirement(.firebase, expectation: .required, platforms: []).applies(environment: .local, platform: .current))
    }

    @Test func unexpectedConfigurationAndWrongProjectAreVisible() {
        let inventory = FoundationDiagnostics(expectations: [.init(.sentry, expectation: .intentionallyUnused)],
            expectedIdentities: [.sentry: .init(projectID: "correct", organization: "owner")])
            .replacing(.sentry) { _ in
                .init(provider: .sentry, configuration: .configured, runtime: .initialized,
                    identityAudit: .init(supplied: .init(projectID: "wrong", organization: "owner"),
                                         running: .init(projectID: "other"), ownership: .external))
            }
        let snapshot = inventory.snapshots(configuration: configuration, preferences: .init())[2]
        #expect(snapshot.findings.contains { $0.code == "unexpected_provider" })
        #expect(snapshot.findings.contains { $0.code == "identity.expected_supplied.project_mismatch" })
        #expect(snapshot.findings.contains { $0.code == "identity.expected_running.project_mismatch" })
        #expect(snapshot.findings.contains { $0.code == "identity.external_initializer" })
        #expect(snapshot.findings.count == Set(snapshot.findings.map(\.id)).count)
    }

    @Test func customServiceInspectionTracksPreferencesAndDoesNotRunActions() {
        var actionsRun = 0
        let action = ProviderVerificationAction(id: "manual", title: "Manual check") { _ in
            actionsRun += 1
            return .init(status: .confirmed, code: "done", message: "Confirmed")
        }
        let inventory = FoundationDiagnostics(actions: [action], additionalInspections: [
            .init(id: "cloudkit") { context in
                .init(id: "cloudkit", title: "CloudKit", summary: context.preferences.diagnostics ? "Enabled" : "Off",
                      details: [.init("container", label: "Container", value: "iCloud.example")], exportableDetailIDs: ["container"])
            },
            .init(id: "cloudkit") { _ in .init(id: "duplicate", title: "Duplicate", summary: "Duplicate") }
        ])
        #expect(inventory.sections(configuration: configuration, preferences: .init()).count == 1)
        #expect(inventory.sections(configuration: configuration, preferences: .init(diagnostics: false))[0].summary == "Off")
        #expect(actionsRun == 0)
    }
}
