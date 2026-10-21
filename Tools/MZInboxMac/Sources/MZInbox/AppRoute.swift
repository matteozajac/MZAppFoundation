import Foundation

struct AppRoute: Codable, Equatable, Identifiable, Sendable {
    var bundleIdentifier: String
    var name: String
    var repository: String
    var mode: Mode = .diagnose
    var enabled = true

    var id: String { bundleIdentifier }

    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case diagnose, fix
        var id: String { rawValue }
        var title: String { self == .diagnose ? "Investigate" : "Prepare a fix" }
        var explanation: String {
            self == .diagnose
                ? "Inspect the report and source, then save findings."
                : "Investigate, prepare changes in a separate Git worktree, and run relevant checks."
        }
    }
}
