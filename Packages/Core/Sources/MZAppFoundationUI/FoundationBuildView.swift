import MZAppFoundation
import SwiftUI

struct FoundationBuildView: View {
    let services: AppServices
    var body: some View {
        let build = services.foundationDiagnostics.buildMetadata
        List {
            Section("App") {
                DiagnosticValueRow("Version", value: services.configuration.version)
                DiagnosticValueRow("Build", value: services.configuration.build)
                DiagnosticValueRow("Bundle ID", value: services.configuration.bundleIdentifier)
                DiagnosticValueRow("Environment", value: services.configuration.environment.rawValue)
                DiagnosticValueRow("Operating system", value: ProcessInfo.processInfo.operatingSystemVersionString)
                DiagnosticValueRow("App revision", value: build.appRevision ?? "Not stamped")
                DiagnosticValueRow("Channel", value: build.buildChannel ?? "Not stamped")
                DiagnosticValueRow("Build date", value: build.buildDate?.formatted() ?? "Not stamped")
                DiagnosticValueRow("App working tree", value: modification(build.appWorkingTreeModified))
            }
            Section("Foundation") {
                DiagnosticValueRow("Version", value: FoundationVersion.current)
                DiagnosticValueRow("Revision", value: build.foundationRevision ?? "Not stamped")
                DiagnosticValueRow("Working tree", value: modification(build.foundationWorkingTreeModified))
                DiagnosticValueRow("Metadata source", value: build.provenance)
            }
            Section("Resolved packages at build time") {
                ForEach(build.resolvedPackageVersions.keys.sorted(), id: \.self) { name in
                    DiagnosticValueRow(name, value: build.resolvedPackageVersions[name] ?? "Unknown")
                }
            }
            Section("Composition") {
                DiagnosticValueRow("Logger", value: services.loggingProvider)
                DiagnosticValueRow("Purchases", value: String(describing: type(of: services.purchases)))
                DiagnosticValueRow("Remote runtime safety", value: services.providerInspectionContext.remoteAllowed ? "Permitted" : "Blocked")
            }
        }
        .navigationTitle("Build information")
    }
    private func modification(_ value: Bool?) -> String { value.map { $0 ? "Modified" : "Clean" } ?? "Not stamped" }
}
