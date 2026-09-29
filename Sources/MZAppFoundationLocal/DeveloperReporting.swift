#if os(iOS)
import MZAppFoundation
import MZAppFoundationReporting
import Pulse
import SwiftUI
import UIKit

/// One reporting instance per app process. Keep it beside the services composition.
/// The host must provide NSMicrophoneUsageDescription before enabling voice reports.
@MainActor public final class DeveloperReporting {
    let coordinator: BugReportCoordinator

    public init(archivePrefix: String = "bug-report", defaults: UserDefaults = .standard,
                preferenceKey: String? = nil, store: LoggerStore = .shared,
                metadata: @escaping @MainActor () -> [String: String] = { [:] }) {
        coordinator = BugReportCoordinator(
            attachmentProvider: PulseReportAttachmentProvider(store: store), defaults: defaults,
            preferenceKey: preferenceKey ?? "\(Bundle.main.bundleIdentifier ?? "MZAppFoundation").recordRecentActivity",
            archivePrefix: archivePrefix, metadata: metadata)
        self.store = store
    }

    private let store: LoggerStore

    public var recordsRecentActivity: Bool {
        get { coordinator.recordingEnabled }
        set { coordinator.recordingEnabled = newValue }
    }

    func present(from window: UIWindow) {
        coordinator.presentPulse(from: window, store: store)
    }
}

/// Place this in the app's developer Settings form.
public struct DeveloperReportingSettings: View {
    private let reporting: DeveloperReporting
    public init(reporting: DeveloperReporting) { self.reporting = reporting }
    public var body: some View { BugRecordingSettings(coordinator: reporting.coordinator) }
}
#endif
