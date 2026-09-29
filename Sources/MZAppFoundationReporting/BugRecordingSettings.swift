#if os(iOS)
import SwiftUI

/// Place inside a Form/Section in the host's developer settings.
public struct BugRecordingSettings: View {
    @Bindable private var coordinator: BugReportCoordinator

    public init(coordinator: BugReportCoordinator) { self.coordinator = coordinator }

    public var body: some View {
        Toggle(BugReportStrings.text("bug_record_recent"), isOn: $coordinator.recordingEnabled)
        LabeledContent(BugReportStrings.text("bug_recording"), value: coordinator.recordingStatus)
        if coordinator.canRetryRecording {
            Button(BugReportStrings.text("bug_retry_recording")) { coordinator.retryRecording() }
        }
    }
}

#endif
