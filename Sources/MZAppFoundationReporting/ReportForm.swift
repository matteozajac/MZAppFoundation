#if os(iOS)
import AVKit
import SwiftUI

struct ReportForm: View {
    @Bindable var draft: ReportDraft
    let discard: () -> Void
    let share: () -> Void
    let retryScreenshot: () -> Void
    let retryVideo: () -> Void
    @State private var confirmDiscard = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    private enum Field: String, Hashable { case title, description, steps, expected }
    @FocusState private var focused: Field?

    var body: some View {
        NavigationStack {
            Form {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(t("bug_report")).font(.headline)
                }
                Section {
                    input("bug_title", text: $draft.report.title, field: .title, lines: 1...3)
                } footer: {
                    Text(t("bug_title_or_audio_help"))
                }
                voiceMessage
                Section {
                    input("bug_description", text: $draft.report.description, field: .description, lines: 3...8)
                    input("bug_steps", text: $draft.report.steps, field: .steps, lines: 2...8)
                    input("bug_expected", text: $draft.report.expectedResult, field: .expected, lines: 2...5)
                    if dynamicTypeSize.isAccessibilitySize { severity.pickerStyle(.inline) } else { severity }
                }
                Section {
                    Toggle(t("bug_share_zip"), isOn: $draft.shareAsZIP)
                        .accessibilityIdentifier("bugReporter.zip")
                } footer: {
                    Text(t("bug_share_zip_help"))
                }
                Section(t("bug_screenshot")) {
                    if let url = draft.screenshot, let image = UIImage(contentsOfFile: url.path) {
                        Toggle(t("bug_include_screenshot"), isOn: $draft.includeScreenshot)
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(t("bug_screenshot"))
                    }
                    if let error = draft.screenshotError {
                        Text(error).foregroundStyle(.secondary)
                        Button(t("bug_retry"), action: retryScreenshot)
                            .disabled(draft.voiceNote.isPreparing || draft.voiceNote.isRecording)
                    }
                }
                Section(t("bug_video")) {
                    if draft.preparingVideo { ProgressView(t("bug_preparing_video")) }
                    if let url = draft.video {
                        Toggle(t("bug_include_video"), isOn: $draft.includeVideo)
                        VideoTrimView(url: url, duration: draft.videoDuration, start: $draft.trimStart, end: $draft.trimEnd)
                    }
                    if let error = draft.videoError {
                        Text(error).foregroundStyle(.secondary)
                        Button(t("bug_retry"), action: retryVideo)
                            .disabled(draft.preparingVideo || draft.voiceNote.isPreparing || draft.voiceNote.isRecording)
                    }
                }
                Section(t("bug_logs")) {
                    Toggle(t("bug_include_logs"), isOn: $draft.includeLogs)
                    Picker(t("bug_log_history"), selection: $draft.logScope) {
                        Text(t("bug_current_session")).tag(BugLogScope.currentSession)
                        Text(t("bug_all_sessions")).tag(BugLogScope.allSessions)
                    }
                    .onChange(of: draft.logScope) { _, _ in Task { await draft.prepareLogs() } }
                    if draft.preparingLogs { ProgressView(t("bug_preparing_logs")) }
                    if let logs = draft.logs, !draft.preparingLogs {
                        LabeledContent("Pulse", value: ByteCountFormatter.string(fromByteCount: Int64((try? logs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file))
                    }
                    if let error = draft.logsError {
                        Text(error).foregroundStyle(.secondary)
                        Button(t("bug_retry")) { Task { await draft.prepareLogs() } }
                    }
                }
                Section(t("bug_details")) {
                    ForEach(draft.report.metadata.sorted { $0.key < $1.key }, id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
                if let error = draft.shareError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(draft.sharing)
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "" : t("bug_report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("bug_done")) { focused = nil }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("bug_cancel")) {
                        if draft.hasEdits { confirmDiscard = true } else { discard() }
                    }.disabled(draft.sharing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { focused = nil; draft.voiceNote.stopPlayback(); share() }) {
                        if draft.sharing { ProgressView() } else { Text(t("bug_share")) }
                    }
                    .accessibilityIdentifier("bugReporter.share")
                    .disabled(!draft.canShare || draft.sharing)
                }
            }
            .confirmationDialog(t("bug_discard_question"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(t("bug_discard"), role: .destructive, action: discard)
                Button(t("bug_keep_editing"), role: .cancel) {}
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { draft.voiceNote.stopPlayback() }
    }

    private var voiceMessage: some View {
        Section {
            if draft.voiceNote.isPreparing {
                ProgressView(t("bug_voice_preparing"))
                    .accessibilityIdentifier("bugReporter.voicePreparing")
            } else if draft.voiceNote.isRecording {
                LabeledContent(t("bug_voice_recording"), value: voiceDuration)
                    .monospacedDigit()
                    .accessibilityIdentifier("bugReporter.voiceDuration")
                Button(t("bug_voice_stop"), systemImage: "stop.fill") { draft.voiceNote.stop() }
                    .tint(.red)
                    .accessibilityIdentifier("bugReporter.voiceStop")
            } else if draft.voiceNote.hasRecording {
                LabeledContent(t("bug_voice_duration"), value: voiceDuration)
                    .monospacedDigit()
                    .accessibilityIdentifier("bugReporter.voiceDuration")
                if draft.voiceNote.isPlaying {
                    Button(t("bug_voice_stop_playback"), systemImage: "stop.fill") { draft.voiceNote.stopPlayback() }
                        .accessibilityIdentifier("bugReporter.voiceStopPlayback")
                } else {
                    Button(t("bug_voice_play"), systemImage: "play.fill") { draft.voiceNote.play() }
                        .accessibilityIdentifier("bugReporter.voicePlay")
                }
                Button(t("bug_voice_delete"), systemImage: "trash", role: .destructive) { draft.voiceNote.remove() }
                    .accessibilityIdentifier("bugReporter.voiceDelete")
            } else {
                Button(t("bug_voice_record"), systemImage: "mic.fill") {
                    focused = nil
                    Task { await draft.voiceNote.start() }
                }
                .accessibilityIdentifier("bugReporter.voiceRecord")
            }
            if let error = draft.voiceNote.error {
                Text(error).foregroundStyle(.secondary)
                    .accessibilityIdentifier("bugReporter.voiceError")
                if draft.voiceNote.permissionDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button(t("bug_voice_settings")) { openURL(settings) }
                }
            }
        } header: {
            Text(t("bug_voice"))
        } footer: {
            Text(t(draft.voiceNote.isRecording ? "bug_voice_limit" : "bug_voice_help"))
        }
    }

    private var voiceDuration: String {
        Duration.seconds(draft.voiceNote.duration).formatted(.time(pattern: .minuteSecond))
    }

    private func input(_ key: String, text: Binding<String>, field: Field, lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(t(key)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TextField(dynamicTypeSize.isAccessibilitySize ? "" : t(key), text: text, axis: .vertical)
                .lineLimit(lines)
                .accessibilityLabel(t(key))
                .accessibilityIdentifier("bugReporter." + field.rawValue)
                .focused($focused, equals: field)
        }
    }

    private var severity: some View {
        Picker(t("bug_severity"), selection: $draft.report.severity) {
            ForEach(["unspecified", "minor", "major", "critical"], id: \.self) { value in
                Text(t("bug_severity_" + value)).tag(value)
            }
        }
    }

    private func t(_ key: String) -> String { BugReportStrings.text(key) }
}

#endif
