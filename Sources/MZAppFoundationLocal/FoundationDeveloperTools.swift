import MZAppFoundation
import MZAppFoundationUI
import PulseUI
import SwiftUI

/// Optional local tools are composed by the host, so the SDK-free UI product stays independent.
@MainActor public enum FoundationDeveloperTools {
    public static func pages(services: AppServices) -> [FoundationDeveloperPage] {
        [.init(id: "mz.console", title: "Pulse console", systemImage: "ladybug") {
            if services.developerOptions.isEnabled {
                #if os(macOS)
                FoundationMacConsole()
                #else
                ConsoleView(store: .shared, mode: .logs)
                #endif
            }
        }]
    }

    #if os(iOS)
    public static func pages(services: AppServices, reporting: DeveloperReporting) -> [FoundationDeveloperPage] {
        [.init(id: "mz.console", title: "Pulse console", systemImage: "ladybug") {
            FoundationReportingView(options: services.developerOptions, reporting: reporting, showsRecordingSettings: false)
        }, .init(id: "mz.reporting", title: "Bug reporting and recording", systemImage: "record.circle") {
            FoundationReportingView(options: services.developerOptions, reporting: reporting)
        }]
    }
    #endif
}
