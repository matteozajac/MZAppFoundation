import Foundation

public enum ProviderExpectation: String, Codable, CaseIterable, Sendable {
    case required, optional, intentionallyUnused
}

public enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case info, warning, error
}

/// Safe, app-owned messages and correction steps. Never include raw vendor errors or credentials.
public struct DiagnosticFinding: Equatable, Codable, Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public let severity: DiagnosticSeverity
    public let message: String
    public let correction: String?
    public init(code: String, severity: DiagnosticSeverity, message: String, correction: String? = nil) {
        self.code = code; self.severity = severity; self.message = message; self.correction = correction
    }
}

public enum ProviderOwnership: String, Codable, Sendable {
    case ownedByComposition, external, notInitialized, unknown
}

public struct ProviderIdentityAudit: Equatable, Codable, Sendable {
    public var expected: ProviderProjectIdentity?
    public var supplied: ProviderProjectIdentity?
    public var running: ProviderProjectIdentity?
    public var ownership: ProviderOwnership

    public init(expected: ProviderProjectIdentity? = nil, supplied: ProviderProjectIdentity? = nil,
                running: ProviderProjectIdentity? = nil, ownership: ProviderOwnership = .unknown) {
        self.expected = expected; self.supplied = supplied; self.running = running; self.ownership = ownership
    }

    public var findings: [DiagnosticFinding] {
        var result: [DiagnosticFinding] = []
        if ownership == .external {
            result.append(.init(code: "identity.external_initializer", severity: .warning,
                message: "The SDK was initialized outside this foundation composition.",
                correction: "Use one app-owned bootstrap and confirm its project before enabling delivery."))
        }
        result += comparisons(expected, supplied, scope: "expected_supplied", description: "Expected and supplied")
        result += comparisons(expected, running, scope: "expected_running", description: "Expected and running")
        result += comparisons(supplied, running, scope: "supplied_running", description: "Supplied and running")
        if (ownership == .ownedByComposition || ownership == .external) && running == nil {
            result.append(.init(code: "identity.runtime_unavailable", severity: .info,
                message: "The SDK does not expose a verifiable running project identity.",
                correction: "Verify the app's supplied project labels against its provider dashboard."))
        }
        return result
    }

    private func comparisons(_ first: ProviderProjectIdentity?, _ second: ProviderProjectIdentity?,
                             scope: String, description: String) -> [DiagnosticFinding] {
        guard let first, let second else { return [] }
        let fields = [("project", first.projectID, second.projectID), ("app", first.appID, second.appID),
                      ("organization", first.organization, second.organization)]
        return fields.compactMap { field, lhs, rhs in
            guard let lhs, !lhs.isEmpty, let rhs, !rhs.isEmpty, lhs != rhs else { return nil }
            return DiagnosticFinding(code: "identity.\(scope).\(field)_mismatch", severity: .error,
                message: "\(description) \(field) identifiers differ.",
                correction: "Replace the target app's configuration with the intended provider project's configuration.")
        }
    }
}
