import Foundation

public struct ProviderInspectionContext: Sendable {
    public let configuration: AppConfiguration
    public let preferences: DeliveryPreferences
    public let remoteAllowed: Bool

    public init(configuration: AppConfiguration, preferences: DeliveryPreferences, remoteAllowed: Bool) {
        self.configuration = configuration; self.preferences = preferences; self.remoteAllowed = remoteAllowed
    }

    public func delivery(configured: Bool, preference: Bool) -> ProviderDeliveryState {
        guard configured else { return .unavailable }
        guard remoteAllowed else { return .runtimeBlocked }
        return preference ? .enabled : .preferenceDisabled
    }
}

/// Injected inspection closures preserve the SDK-free core and read current adapter state.
@MainActor public struct FoundationDiagnostics {
    public typealias Inspection = @MainActor (ProviderInspectionContext) -> ProviderSnapshot
    private var inspections: [FoundationProvider: Inspection]
    public var bootstrapIssue: String?
    public var expectations: [ProviderRequirement]
    public var expectedIdentities: [FoundationProvider: ProviderProjectIdentity]
    public var startupRecords: [ProviderStartupRecord]
    public var buildMetadata: FoundationBuildMetadata
    public var actions: [ProviderVerificationAction]
    public var purchaseDiagnostics: (@MainActor () -> PurchaseDiagnosticsSnapshot?)?
    public var additionalInspections: [FoundationDiagnosticInspection]

    public init(bundle: Bundle = .main, inspections: [FoundationProvider: Inspection] = [:],
                bootstrapIssue: String? = nil, expectations: [ProviderRequirement] = [],
                expectedIdentities: [FoundationProvider: ProviderProjectIdentity] = [:],
                startupRecords: [ProviderStartupRecord] = [], buildMetadata: FoundationBuildMetadata = .current(),
                actions: [ProviderVerificationAction] = [],
                purchaseDiagnostics: (@MainActor () -> PurchaseDiagnosticsSnapshot?)? = nil,
                additionalInspections: [FoundationDiagnosticInspection] = []) {
        self.inspections = inspections
        self.bootstrapIssue = bootstrapIssue
        self.expectations = expectations; self.expectedIdentities = expectedIdentities
        self.startupRecords = startupRecords; self.buildMetadata = buildMetadata
        self.actions = actions; self.purchaseDiagnostics = purchaseDiagnostics
        self.additionalInspections = additionalInspections
        if self.inspections[.firebase] == nil {
            let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist")
            self.inspections[.firebase] = { context in
                let file = FirebaseConfigurationInspection.inspect(bundleIdentifier: context.configuration.bundleIdentifier, path: path)
                let projectID = file.details.first { $0.id == "PROJECT_ID" }?.value
                let appID = file.details.first { $0.id == "GOOGLE_APP_ID" }?.value
                return ProviderSnapshot(provider: .firebase, configuration: file.state, details: file.details,
                    explanation: file.explanation + " The Firebase adapter is not linked to this composition.",
                    identityAudit: .init(supplied: projectID == nil && appID == nil ? nil : .init(projectID: projectID, appID: appID),
                                         ownership: .notInitialized))
            }
        }
    }

    public func replacing(_ provider: FoundationProvider, inspection: @escaping Inspection) -> Self {
        var result = self
        result.inspections[provider] = inspection
        return result
    }

    public func snapshots(configuration: AppConfiguration, preferences: DeliveryPreferences) -> [ProviderSnapshot] {
        let context = ProviderInspectionContext(configuration: configuration, preferences: preferences,
                                               remoteAllowed: RuntimeSafety.permitsRemote(environment: configuration.environment))
        return FoundationProvider.allCases.map { provider in
            var snapshot = inspections[provider]?(context) ?? ProviderSnapshot(provider: provider,
                explanation: "The \(provider.name) adapter is not linked to this composition. No provider configuration was supplied.",
                identityAudit: .init(ownership: .notInitialized))
            snapshot.expectation = expectations.last {
                $0.provider == provider && $0.applies(environment: configuration.environment, platform: .current)
            }?.expectation ?? .optional
            if let expected = expectedIdentities[provider] { snapshot.identityAudit.expected = expected }
            snapshot.findings += snapshot.identityAudit.findings
            if snapshot.configuration == .invalid {
                snapshot.findings.append(.init(code: "invalid_configuration", severity: .error,
                    message: "The supplied \(provider.name) configuration is invalid.",
                    correction: "Replace it with configuration for this app's bundle and provider project."))
            }
            if snapshot.runtime == .failed {
                snapshot.findings.append(.init(code: "bootstrap_failed", severity: .error,
                    message: "\(provider.name) did not complete startup.",
                    correction: "Review Startup history for the failing stage and recovery step."))
            }
            if snapshot.expectation == .required {
                if snapshot.configuration != .configured {
                    snapshot.findings.append(.init(code: "required_configuration", severity: .error,
                        message: "This app requires \(provider.name), but its configuration is unavailable or invalid.",
                        correction: "Supply valid configuration for this app, environment and platform."))
                }
                if snapshot.runtime == .notLinked || snapshot.runtime == .unsupported {
                    snapshot.findings.append(.init(code: "required_adapter", severity: .error,
                        message: "The required \(provider.name) adapter is unavailable in this composition.",
                        correction: "Link the supported adapter or narrow this app's provider requirement."))
                }
            } else if snapshot.expectation == .intentionallyUnused &&
                        (snapshot.configuration == .configured || snapshot.runtime == .initialized) {
                snapshot.findings.append(.init(code: "unexpected_provider", severity: .warning,
                    message: "\(provider.name) is present although this composition declares it unused.",
                    correction: "Remove its configuration or update the declared provider expectation."))
            }
            var findingIDs = Set<String>()
            snapshot.findings = snapshot.findings.filter { findingIDs.insert($0.id).inserted }
            return snapshot
        }
    }

    public func adding(action: ProviderVerificationAction) -> Self {
        var result = self
        result.actions.removeAll { $0.id == action.id }
        result.actions.append(action)
        return result
    }

    public func recordingStartup(_ records: [ProviderStartupRecord]) -> Self {
        var result = self; result.startupRecords += records; return result
    }

    public func replacing(purchaseDiagnostics: @escaping @MainActor () -> PurchaseDiagnosticsSnapshot?) -> Self {
        var result = self; result.purchaseDiagnostics = purchaseDiagnostics; return result
    }

    public func sections(configuration: AppConfiguration, preferences: DeliveryPreferences) -> [FoundationDiagnosticSection] {
        let context = ProviderInspectionContext(configuration: configuration, preferences: preferences,
            remoteAllowed: RuntimeSafety.permitsRemote(environment: configuration.environment))
        var seen = Set<String>()
        return additionalInspections.compactMap { inspection in
            guard seen.insert(inspection.id).inserted else { return nil }
            return inspection.inspect(context: context)
        }
    }
}
