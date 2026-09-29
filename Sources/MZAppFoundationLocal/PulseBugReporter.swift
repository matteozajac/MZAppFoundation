#if os(iOS)
import MZAppFoundationReporting
import CoreData
import Pulse
import PulseUI
import SwiftUI
import UIKit

@MainActor public final class PulseReportAttachmentProvider: BugReportAttachmentProvider {
    private let store: LoggerStore

    public init(store: LoggerStore = .shared) { self.store = store }

    public func exportLogs(to directory: URL, scope: BugLogScope) async throws -> URL {
        // Save queued records before exporting, including errors logged just before shaking.
        let context = store.backgroundContext
        try await context.perform {
            if context.hasChanges { try context.save() }
        }
        let url = directory.appendingPathComponent("logs.pulse")
        let options = LoggerStore.ExportOptions(sessions: scope == .currentSession ? [store.session.id] : nil)
        try await store.export(to: url, options: options)
        return url
    }
}

@MainActor public extension BugReportCoordinator {
    func presentPulse(from window: UIWindow, store: LoggerStore = .shared) {
        presentConsole(from: window) { ConsoleView(store: store, mode: .logs) }
    }
}

#endif
