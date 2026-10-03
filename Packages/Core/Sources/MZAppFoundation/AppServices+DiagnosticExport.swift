import Foundation

public extension AppServices {
    /// Inspection only: does not initialize providers, perform requests, or change delivery preferences.
    func diagnosticExport() -> FoundationDiagnosticExport { FoundationDiagnosticExport(services: self) }
}
