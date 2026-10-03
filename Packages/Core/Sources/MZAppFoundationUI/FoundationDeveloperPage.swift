import MZAppFoundation
import SwiftUI

/// App-owned destinations share the foundation's developer-access gate.
@MainActor public struct FoundationDeveloperPage: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    private let content: @MainActor () -> AnyView

    public init<Content: View>(id: String, title: String, systemImage: String = "wrench.and.screwdriver",
                              @ViewBuilder content: @escaping @MainActor () -> Content) {
        self.id = id; self.title = title; self.systemImage = systemImage
        self.content = { AnyView(content()) }
    }

    func makeView() -> AnyView { content() }
}

enum FoundationSettingsRoute: Hashable {
    case provider(FoundationProvider)
    case section(String), page(String)
    case build, startup, telemetry, timeline, links, export, qa, access
}
