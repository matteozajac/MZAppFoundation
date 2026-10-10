#if os(iOS)
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
public final class BugReportCoordinator {
    public var recordingEnabled: Bool {
        didSet {
            defaults.set(recordingEnabled, forKey: preferenceKey)
            updateRecording()
        }
    }
    public var recordingStatus: String { recording?.status ?? storageError ?? BugReportStrings.text("bug_recording_off") }
    public var isRecording: Bool { recording?.isRecording ?? false }
    public var canRetryRecording: Bool { developerMode && recordingEnabled && !isRecording }
    public private(set) var presentationError: String?

    private let defaults: UserDefaults
    private let preferenceKey: String
    private let provider: any BugReportAttachmentProvider
    private let archivePrefix: String
    private let metadata: @MainActor () -> [String: String]
    private let diagnostics: (@MainActor () throws -> Data)?
    private let files: ReportFiles?
    private let storageError: String?
    private let recording: RecordingSession?
    private var developerMode = false
    private var active = false
    private var busy = false
    private var finishing = false
    private(set) var draft: ReportDraft?
    private var capturedReport: BugReport?
    private var capturedDiagnostics = ReportDiagnosticsCapture.notProvided
    private var frozen: RollingVideoBuffer?
    private var preparation: Task<Void, Never>?
    private var sharingTask: Task<Void, Never>?
    private var presentationID: UUID?
    private weak var window: UIWindow?
    private weak var presenter: UIViewController?
    private weak var consoleHost: UIViewController?
    private weak var formHost: UIViewController?
    private var overlay: DeveloperOverlayWindow?
    private var movingFromConsole = false

    public init(
        attachmentProvider: any BugReportAttachmentProvider,
        defaults: UserDefaults = .standard,
        preferenceKey: String = "BugReporter.recordRecentActivity",
        archivePrefix: String = "bug-report",
        metadata: @escaping @MainActor () -> [String: String] = { [:] },
        diagnostics: (@MainActor () throws -> Data)? = nil
    ) {
        self.provider = attachmentProvider
        self.archivePrefix = archivePrefix
        self.defaults = defaults
        self.preferenceKey = preferenceKey
        self.metadata = metadata
        self.diagnostics = diagnostics
        recordingEnabled = defaults.object(forKey: preferenceKey) as? Bool ?? false
        do {
            let files = try ReportFiles()
            files.clearAbandoned()
            self.files = files
            recording = RecordingSession(files: files)
            storageError = nil
        } catch {
            files = nil
            recording = nil
            storageError = error.localizedDescription
        }
    }

    /// The host gates this coordinator with its own QA build flag.
    public func update(developerMode: Bool, isActive: Bool) {
        self.developerMode = developerMode
        active = isActive
        if !developerMode { dismiss() }
        updateRecording()
    }

    fileprivate func dismissPresentationError() { presentationError = nil }

    public func retryRecording() { recording?.retry() }

    public func presentConsole<Content: View>(from window: UIWindow, @ViewBuilder content: () -> Content) {
        guard !busy, let overlay = DeveloperOverlayWindow(from: window) else { return }
        self.overlay = overlay
        let presenter = overlay.presenter
        busy = true
        presentationID = UUID()
        self.window = window
        self.presenter = presenter
        capturedReport = .make(metadata: metadata())
        capturedDiagnostics = .capture(diagnostics)
        frozen = recording?.freeze()
        let shell = ConsoleShell(coordinator: self, content: content(),
                                 close: { [weak self] in self?.dismiss() },
                                 report: { [weak self] in self?.beginReport() })
        let host = DismissAwareHost(rootView: shell)
        host.didDismiss = { [weak self] in
            guard let self, !movingFromConsole else { return }
            finish()
        }
        consoleHost = host
        presenter.present(host, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    public func dismiss() {
        guard let overlay else { return }
        overlay.presenter.dismiss(animated: false)
        finish()
    }

    private func updateRecording() {
        recording?.update(enabled: developerMode && recordingEnabled, active: active)
    }

    func beginReport() {
        guard !movingFromConsole, let consoleHost, let window, let files else {
            presentationError = storageError
            return
        }
        do {
            draft = ReportDraft(report: capturedReport ?? .make(metadata: metadata()), directory: try files.directory(), provider: provider, archivePrefix: archivePrefix,
                                diagnostics: capturedDiagnostics)
        } catch {
            presentationError = error.localizedDescription
            return
        }
        let presentationID = self.presentationID
        movingFromConsole = true
        consoleHost.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await RenderFrame.wait()
                guard self.presentationID == presentationID, self.overlay != nil else { return }
                // Release ReplayKit before the form can start microphone capture.
                await self.recording?.waitUntilSettled()
                guard self.presentationID == presentationID, self.overlay != nil, let draft = self.draft else { return }
                draft.capture(window: window)
                self.showForm(draft)
                let buffer = self.frozen
                self.preparation = Task {
                    async let video: Void = draft.prepareVideo(buffer)
                    async let logs: Void = draft.prepareLogs()
                    _ = await (video, logs)
                }
            }
        }
    }

    private func showForm(_ draft: ReportDraft) {
        guard let presenter, presenter.view.window != nil else { finish(); return }
        let view = ReportForm(draft: draft, discard: { [weak self] in self?.dismissForm() },
                              share: { [weak self] in self?.share() },
                              retryScreenshot: { [weak self] in self?.retryScreenshot() },
                              retryVideo: { [weak self] in self?.retryVideo() })
        let host = UIHostingController(rootView: view)
        host.isModalInPresentation = true
        formHost = host
        presenter.present(host, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func retryScreenshot() {
        guard let formHost, let window, let draft else { return }
        let presentationID = self.presentationID
        formHost.dismiss(animated: false) { [weak self] in
            Task { @MainActor in
                await RenderFrame.wait()
                guard let self, self.presentationID == presentationID, self.draft === draft, self.overlay != nil else { return }
                draft.capture(window: window)
                self.showForm(draft)
            }
        }
    }

    private func retryVideo() {
        guard let draft, !draft.preparingVideo else { return }
        preparation = Task { [weak self] in
            guard let self else { return }
            await draft.prepareVideo(frozen)
        }
    }

    private func share() {
        guard let draft, draft.canShare, !draft.sharing, let formHost else { return }
        draft.sharing = true
        sharingTask = Task { [weak self] in
            do {
                let items = try await draft.shareItems()
                guard !Task.isCancelled, self?.draft === draft, self?.formHost === formHost else { return }
                let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
                let title = draft.report.title.trimmingCharacters(in: .whitespacesAndNewlines)
                activity.setValue(title.isEmpty ? BugReportStrings.text("bug_report") : title, forKey: "subject")
                activity.popoverPresentationController?.sourceView = formHost.view
                activity.popoverPresentationController?.sourceRect = CGRect(x: formHost.view.bounds.midX, y: formHost.view.bounds.maxY - 1, width: 1, height: 1)
                activity.completionWithItemsHandler = { [weak self, weak activity] _, completed, _, error in
                    Task { @MainActor in
                        guard self?.draft === draft, self?.formHost === formHost else { return }
                        draft.sharing = false
                        if let error { draft.shareError = error.localizedDescription }
                        if completed {
                            // Wait for the activity controller's dismissal before closing its presenter.
                            if let activity, activity.presentingViewController != nil {
                                activity.dismiss(animated: true) { self?.dismissForm() }
                            } else {
                                self?.dismissForm()
                            }
                        }
                    }
                }
                formHost.present(activity, animated: true)
            } catch {
                guard self?.draft === draft else { return }
                draft.sharing = false
                draft.shareError = error.localizedDescription
            }
        }
    }

    private func dismissForm() {
        guard let formHost else { finish(); return }
        formHost.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard busy, !finishing else { return }
        finishing = true
        presentationID = nil
        overlay?.close()
        overlay = nil
        consoleHost = nil
        formHost = nil
        presenter = nil
        let pendingDraft = draft
        pendingDraft?.voiceNote.cancel()
        let draftDirectory = draft?.directory
        let buffer = frozen
        let work = preparation
        let sharing = sharingTask
        sharing?.cancel()
        draft = nil
        capturedReport = nil
        capturedDiagnostics = .notProvided
        frozen = nil
        preparation = nil
        sharingTask = nil
        movingFromConsole = false
        Task { [weak self] in
            await work?.value
            await sharing?.value
            await pendingDraft?.waitForExports()
            _ = try? await buffer?.snapshot()
            guard let self else { return }
            if let draftDirectory { files?.remove(draftDirectory) }
            if let directory = buffer?.directory { files?.remove(directory) }
            busy = false
            finishing = false
            recording?.resume()
        }
    }
}

private struct ConsoleShell<Content: View>: View {
    @Bindable var coordinator: BugReportCoordinator
    let content: Content
    let close: () -> Void
    let report: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(BugReportStrings.text("bug_done"), action: close)
                            .accessibilityIdentifier("bugReporter.closeConsole")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(BugReportStrings.text("bug_share_bug"), systemImage: "ladybug", action: report)
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("bugReporter.shareBug")
                    }
                }
        }
        .alert(BugReportStrings.text("bug_report"), isPresented: Binding(
            get: { coordinator.presentationError != nil },
            set: { if !$0 { coordinator.dismissPresentationError() } }
        )) {
            Button(BugReportStrings.text("bug_done")) { coordinator.dismissPresentationError() }
        } message: {
            Text(coordinator.presentationError ?? "")
        }
    }
}

private final class DismissAwareHost<Content: View>: UIHostingController<Content> {
    var didDismiss: (() -> Void)?
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController == nil || isBeingDismissed { didDismiss?() }
    }
}

/// A display-link boundary avoids timing guesses and respects the originating scene.
@MainActor private final class RenderFrame: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?

    static func wait() async {
        let frame = RenderFrame()
        await withCheckedContinuation { continuation in
            frame.continuation = continuation
            let link = CADisplayLink(target: frame, selector: #selector(frame.tick))
            frame.link = link
            link.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick() {
        link?.invalidate()
        link = nil
        continuation?.resume()
        continuation = nil
    }
}

#endif
