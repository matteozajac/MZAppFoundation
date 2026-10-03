import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

@main struct SampleApp: App {
    @State private var services = SampleBootstrap.make()
    var body: some Scene {
        WindowGroup {
            SampleView(services: services)
                #if os(iOS)
                .appDeveloperTools(services.developerOptions, reporting: SampleBootstrap.reporting)
                #else
                .appDeveloperTools(services.developerOptions)
                #endif
        }
        #if os(visionOS) || os(macOS)
        DeveloperConsoleScene(options: services.developerOptions)
        FoundationSettingsScene(services: services, pages: FoundationDeveloperTools.pages(services: services))
        #if os(macOS)
            .commands { FoundationSettingsCommands(services: services) }
        #endif
        #endif
    }
}
