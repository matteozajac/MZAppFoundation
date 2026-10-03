import Foundation
import MZAppFoundation

@MainActor public enum SentryProvider {
    public static func isValidDSN(_ dsn: String) -> Bool {
        guard let parts = URLComponents(string: dsn), let host = parts.host, !host.isEmpty,
              let key = parts.user, !key.isEmpty,
              let projectID = parts.path.split(separator: "/").last, !projectID.isEmpty,
              projectID.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return false }
        return parts.scheme == "https" && parts.password == nil && parts.query == nil && parts.fragment == nil
    }
    public static func identity(fromDSN dsn: String) -> ProviderProjectIdentity? {
        guard isValidDSN(dsn), let parts = URLComponents(string: dsn),
              let projectID = parts.path.split(separator: "/").last else { return nil }
        return .init(projectID: String(projectID))
    }
    public static func diagnostics(dsn: String?, project: ProviderProjectIdentity = .init(),
                                   base: FoundationDiagnostics = .init(), bootstrapFailure: Bool = false,
                                   engine: SentryDiagnostics? = nil) -> FoundationDiagnostics {
        let inspection = base.replacing(.sentry) { context in
            let valid = dsn.map(isValidDSN) ?? false
            let state: ProviderConfigurationState = dsn == nil ? .notConfigured : (valid ? .configured : .invalid)
            var details = project.details
            details.append(.init("dsn", label: "Client DSN", value: dsn == nil ? "Missing" : (valid ? "Present · hidden" : "Invalid · hidden")))
            if valid, let dsn, let parts = URLComponents(string: dsn) {
                if let host = parts.host { details.append(.init("server", label: "Ingestion server", value: host)) }
                if let projectID = identity(fromDSN: dsn)?.projectID { details.append(.init("dsnProject", label: "DSN project ID", value: projectID)) }
            }
            let ownership: ProviderOwnership = SentryDiagnostics.ownership == .notInitialized ? .notInitialized
                : (engine?.ownsRunningSDK == true ? .ownedByComposition : .external)
            let supplied = ProviderProjectIdentity(name: project.name,
                projectID: dsn.flatMap(identity(fromDSN:))?.projectID ?? project.projectID,
                appID: project.appID, organization: project.organization)
            var findings: [DiagnosticFinding] = []
            if let declared = project.projectID, !declared.isEmpty, let configured = supplied.projectID,
               !configured.isEmpty, declared != configured {
                findings.append(.init(code: "identity.sentry.declared_dsn_project_mismatch", severity: .error,
                    message: "The app's declared Sentry project ID differs from its DSN project ID.",
                    correction: "Use this app's intended project ID and the DSN issued for that same project."))
            }
            return ProviderSnapshot(provider: .sentry, sdkVersion: FoundationVersion.resolvedPackageVersions["sentry-cocoa"], versionSource: "Generated foundation Package.resolved snapshot",
                configuration: state, runtime: bootstrapFailure ? .failed : (!context.remoteAllowed && valid ? .suppressed
                    : (ownership == .notInitialized ? .notInitialized : .initialized)),
                delivery: bootstrapFailure ? .unavailable : (!context.remoteAllowed || !context.preferences.diagnostics
                    ? context.delivery(configured: valid, preference: context.preferences.diagnostics)
                    : (valid && ownership == .ownedByComposition ? .enabled : .unavailable)), details: details,
                explanation: "The supplied DSN project is derived without exposing the DSN. The pinned SDK does not expose a supported running project identity. Initialization ownership is tracked separately. Crash ingestion and symbol uploads require separate verification.",
                identityAudit: .init(supplied: supplied, running: SentryDiagnostics.runningIdentity, ownership: ownership),
                findings: findings)
        }
        guard let engine else { return inspection }
        return inspection.adding(action: .init(id: "sentry.submit_verification", title: "Submit a tagged Sentry event", provider: .sentry) {
            [weak engine] context in
            guard let engine else { return .init(status: .unavailable, code: "sentry.provider_unavailable", message: "The Sentry provider is unavailable.") }
            return engine.submitVerification(context: context)
        })
    }
}
