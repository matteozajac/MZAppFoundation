import SwiftUI
import Testing
import UIKit
@testable import MZAppFoundationReporting

extension DeveloperPresentationTests {
    @Test(.timeLimit(.minutes(1)))
    func disablingReportWaitsForExportAndPreservesOriginalAlert() async throws {
        let suite = "ReportingPresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: "recording")
        defer { defaults.removePersistentDomain(forName: suite) }

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let origin = UIWindow(windowScene: scene)
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        origin.rootViewController = root
        origin.makeKeyAndVisible()

        let provider = ReportingExportGate()
        let coordinator = BugReportCoordinator(attachmentProvider: provider, defaults: defaults,
                                               preferenceKey: "recording")
        defer {
            provider.release()
            coordinator.update(developerMode: false, isActive: true)
            root.dismiss(animated: false)
            origin.isHidden = true
            previousKeyWindow?.makeKey()
        }
        try await waitForReporting { root.view.window === origin }
        let alert = UIAlertController(title: "Original app alert", message: "Pending choice", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
        root.present(alert, animated: false)
        try await waitForReporting { alert.view.window === origin }

        coordinator.update(developerMode: true, isActive: true)
        coordinator.presentConsole(from: origin) { Text("First console") }
        try await waitForReporting { reportingConsoleIsReady(in: scene, above: origin) }
        let firstOverlay = try #require(reportingWindow(in: scene, above: origin))
        #expect(root.presentedViewController === alert)
        coordinator.beginReport()
        try await waitForReporting { provider.requestCount == 1 && coordinator.draft != nil }
        let firstDraft = try #require(coordinator.draft)
        let firstDirectory = firstDraft.directory
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))

        coordinator.update(developerMode: false, isActive: true)
        coordinator.dismiss()
        coordinator.dismiss()
        try await waitForReporting { origin.isKeyWindow && firstOverlay.isHidden }
        for _ in 0..<20 { await Task.yield() }
        #expect(coordinator.draft == nil)
        #expect(root.presentedViewController === alert)
        #expect(alert.view.window === origin)
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))

        coordinator.update(developerMode: true, isActive: true)
        coordinator.presentConsole(from: origin) { Text("Cannot reopen during cleanup") }
        #expect(origin.isKeyWindow)
        #expect(reportingWindow(in: scene, above: origin) == nil)
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))

        provider.release()
        try await waitForReporting { !FileManager.default.fileExists(atPath: firstDirectory.path) }
        coordinator.presentConsole(from: origin) { Text("Current console") }
        try await waitForReporting { reportingConsoleIsReady(in: scene, above: origin) }
        let currentOverlay = try #require(reportingWindow(in: scene, above: origin))
        #expect(currentOverlay !== firstOverlay)
        coordinator.beginReport()
        try await waitForReporting { provider.requestCount == 2 && coordinator.draft != nil }
        let currentDraft = try #require(coordinator.draft)
        for _ in 0..<20 { await Task.yield() }
        #expect(coordinator.draft === currentDraft)
        #expect(currentOverlay.isKeyWindow)
        #expect(!currentOverlay.isHidden)
        #expect(FileManager.default.fileExists(atPath: currentDraft.directory.path))
        #expect(root.presentedViewController === alert)
        #expect(alert.title == "Original app alert")

        coordinator.dismiss()
        try await waitForReporting { !FileManager.default.fileExists(atPath: currentDraft.directory.path) && origin.isKeyWindow }
        #expect(root.presentedViewController === alert)
    }

    private func reportingWindow(in scene: UIWindowScene, above origin: UIWindow) -> UIWindow? {
        scene.windows.first { $0 !== origin && $0.isKeyWindow && !$0.isHidden }
    }

    private func reportingConsoleIsReady(in scene: UIWindowScene, above origin: UIWindow) -> Bool {
        guard let console = reportingWindow(in: scene, above: origin)?.rootViewController?.presentedViewController else { return false }
        return console.view.window != nil && !console.isBeingPresented && !console.isBeingDismissed
    }

    private func waitForReporting(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        try #require(predicate())
    }
}

@MainActor private final class ReportingExportGate: BugReportAttachmentProvider {
    private(set) var requestCount = 0
    private var blocked = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func exportLogs(to directory: URL, scope: BugLogScope) async throws -> URL {
        requestCount += 1
        if blocked { await withCheckedContinuation { waiters.append($0) } }
        let url = directory.appendingPathComponent("logs.pulse")
        try Data("Reporting lifecycle fixture".utf8).write(to: url)
        return url
    }

    func release() {
        blocked = false
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}
