import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI

@main struct SampleApp: App {
    @State private var services = SampleBootstrap.make()
    var body: some Scene {
        WindowGroup {
            SampleView(services: services)
                .appDeveloperTools(services.developerOptions)
        }
        #if os(visionOS)
        DeveloperConsoleScene(options: services.developerOptions)
        #endif
    }
}
