import Foundation

/// A passive, app-owned service inspection. Values must be safe technical configuration, never customer data.
public struct FoundationDiagnosticSection: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public var summary: String
    public var details: [ProviderDetail]
    public var findings: [DiagnosticFinding]
    /// Export is opt-in per field; UI-only inspection values remain in the app.
    public var exportableDetailIDs: Set<String>

    public init(id: String, title: String, summary: String, details: [ProviderDetail] = [],
                findings: [DiagnosticFinding] = [], exportableDetailIDs: Set<String> = []) {
        self.id = id; self.title = title; self.summary = summary
        self.details = details; self.findings = findings
        self.exportableDetailIDs = exportableDetailIDs
    }
}

@MainActor public struct FoundationDiagnosticInspection {
    public let id: String
    private let inspection: @MainActor (ProviderInspectionContext) -> FoundationDiagnosticSection

    public init(id: String, inspection: @escaping @MainActor (ProviderInspectionContext) -> FoundationDiagnosticSection) {
        self.id = id; self.inspection = inspection
    }

    public func inspect(context: ProviderInspectionContext) -> FoundationDiagnosticSection {
        inspection(context)
    }
}
