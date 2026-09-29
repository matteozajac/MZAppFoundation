#if os(iOS)
import AVFAudio
import AudioToolbox
import Observation
import UIKit

@MainActor @Observable
final class VoiceNoteRecorder: NSObject {
    static let maximumDuration: TimeInterval = 300
    static let minimumDuration: TimeInterval = 0.5

    private(set) var url: URL?
    private(set) var duration: TimeInterval = 0
    private(set) var bitRate: Int?
    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var isPlaying = false
    private(set) var permissionDenied = false
    private(set) var error: String?

    var hasRecording: Bool { url != nil }
    var hasEdits: Bool { hasRecording || isRecording || isPreparing }

    private let directory: URL
    private let requestPermission: @MainActor () async -> Bool
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var clock: Task<Void, Never>?
    private var generation = UUID()
    private var previousCategory: AVAudioSession.Category?
    private var previousMode: AVAudioSession.Mode?
    private var previousOptions: AVAudioSession.CategoryOptions = []

    init(directory: URL, requestPermission: @escaping @MainActor () async -> Bool = { await AVAudioApplication.requestRecordPermission() }) {
        self.directory = directory
        self.requestPermission = requestPermission
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioWasInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(audioServicesWereReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func start() async {
        guard !isPreparing, !isRecording, !hasRecording else { return }
        stopPlayback()
        error = nil
        permissionDenied = false
        isPreparing = true
        let request = UUID()
        generation = request

        let granted = await requestPermission()
        guard request == generation else { return }
        guard !Task.isCancelled, UIApplication.shared.applicationState != .background else {
            isPreparing = false
            return
        }
        guard granted else {
            isPreparing = false
            permissionDenied = true
            error = text("bug_voice_permission")
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try activateAudioSession(category: .record, mode: .measurement, options: [.allowBluetoothHFP])
            let candidate = directory.appendingPathComponent("voice-note.m4a")
            var settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            var recorder = try AVAudioRecorder(url: candidate, settings: settings)
            if !recorder.prepareToRecord() {
                // Some audio encoders reject a requested bitrate. Preserve AAC,
                // sample rate and channels while letting the encoder choose its rate.
                recorder.stop()
                try? FileManager.default.removeItem(at: candidate)
                settings.removeValue(forKey: AVEncoderBitRateKey)
                recorder = try AVAudioRecorder(url: candidate, settings: settings)
                self.recorder = recorder
                guard recorder.prepareToRecord() else {
                    throw CaptureError.failed(text("bug_voice_failed"))
                }
            }
            self.recorder = recorder
            recorder.delegate = self
            guard recorder.record(forDuration: Self.maximumDuration) else {
                throw CaptureError.failed(text("bug_voice_failed"))
            }
            duration = 0
            isPreparing = false
            isRecording = true
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    guard let self, self.isRecording, let recorder = self.recorder else { return }
                    self.duration = min(recorder.currentTime, Self.maximumDuration)
                }
            }
        } catch {
            removeUnfinishedRecording()
            isPreparing = false
            self.error = text("bug_voice_failed")
            releaseAudioSession()
        }
    }

    func stop() {
        guard isRecording, let recorder else { return }
        isRecording = false
        isPreparing = true
        clock?.cancel()
        clock = nil
        recorder.stop()
        // The delegate validates the finalized file before it becomes shareable.
    }

    func play() {
        guard !isPreparing, !isRecording, !isPlaying, let url else { return }
        error = nil
        do {
            try activateAudioSession(category: .playback, mode: .spokenAudio)
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.delegate = self
            guard player.prepareToPlay(), player.play() else {
                throw CaptureError.failed(text("bug_voice_playback_failed"))
            }
            isPlaying = true
        } catch {
            stopPlayback()
            self.error = text("bug_voice_playback_failed")
        }
    }

    func stopPlayback() {
        player?.delegate = nil
        player?.stop()
        player = nil
        isPlaying = false
        if !isRecording, recorder == nil { releaseAudioSession() }
    }

    func remove() {
        cancel()
    }

    func cancel() {
        generation = UUID()
        stopPlayback()
        removeUnfinishedRecording()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        bitRate = nil
        duration = 0
        isPreparing = false
        error = nil
        releaseAudioSession()
    }

    /// Validates a completed file before accepting it into the report. Keeping this
    /// separate also lets export tests exercise real AAC files without microphone access.
    func acceptCompletedRecording(at candidate: URL) throws {
        guard !isRecording,
              candidate.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              candidate.pathExtension.lowercased() == "m4a",
              (try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
            throw CaptureError.failed(text("bug_voice_failed"))
        }
        let audio = try AVAudioFile(forReading: candidate)
        let format = audio.fileFormat.streamDescription.pointee
        let length = Double(audio.length) / audio.processingFormat.sampleRate
        guard format.mFormatID == kAudioFormatMPEG4AAC,
              format.mChannelsPerFrame == 1,
              format.mSampleRate == 24_000,
              length.isFinite, length <= Self.maximumDuration + 0.25 else {
            throw CaptureError.failed(text("bug_voice_failed"))
        }
        guard length >= Self.minimumDuration else {
            throw CaptureError.failed(text("bug_voice_too_short"))
        }
        url = candidate
        duration = min(length, Self.maximumDuration)
        bitRate = Self.encodedBitRate(at: candidate)
    }

    private static func encodedBitRate(at url: URL) -> Int? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return nil }
        defer { AudioFileClose(file) }
        var rate: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyBitRate, &size, &rate) == noErr, rate > 0 else { return nil }
        return Int(rate)
    }

    private func finishRecording(for identifier: ObjectIdentifier, successfully: Bool, interrupted: Bool = false) {
        guard let recorder, ObjectIdentifier(recorder) == identifier else { return }
        isRecording = false
        isPreparing = true
        clock?.cancel()
        clock = nil
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil
        defer {
            isPreparing = false
            releaseAudioSession()
        }
        do {
            guard successfully else { throw CaptureError.failed(text("bug_voice_failed")) }
            try acceptCompletedRecording(at: recorder.url)
            error = interrupted ? text("bug_voice_interrupted") : nil
        } catch {
            try? FileManager.default.removeItem(at: recorder.url)
            url = nil
            bitRate = nil
            duration = 0
            self.error = (error as? CaptureError)?.localizedDescription ?? text("bug_voice_failed")
        }
    }

    private func removeUnfinishedRecording() {
        clock?.cancel()
        clock = nil
        recorder?.delegate = nil
        recorder?.stop()
        if let candidate = recorder?.url { try? FileManager.default.removeItem(at: candidate) }
        recorder = nil
        isRecording = false
        duration = 0
    }

    private func activateAudioSession(category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions = []) throws {
        let session = AVAudioSession.sharedInstance()
        previousCategory = session.category
        previousMode = session.mode
        previousOptions = session.categoryOptions
        try session.setCategory(category, mode: mode, options: options)
        try session.setActive(true)
    }

    private func releaseAudioSession() {
        guard let category = previousCategory, let mode = previousMode else { return }
        previousCategory = nil
        previousMode = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(category, mode: mode, options: previousOptions)
    }

    private func interrupt() {
        generation = UUID()
        if let recorder {
            // AVAudioRecorder does not send its finish delegate callback for an
            // interruption, so explicitly stop and validate the partial recording.
            finishRecording(for: ObjectIdentifier(recorder), successfully: true, interrupted: true)
        } else {
            isPreparing = false
        }
        stopPlayback()
    }

    @objc nonisolated private func audioWasInterrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor [weak self] in self?.interrupt() }
    }

    @objc nonisolated private func appEnteredBackground(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.interrupt() }
    }

    @objc nonisolated private func audioServicesWereReset(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.interrupt() }
    }

    @objc nonisolated private func audioRouteChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in self?.interrupt() }
    }

    private func text(_ key: String) -> String { BugReportStrings.text(key) }
}

extension VoiceNoteRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in self?.finishRecording(for: identifier, successfully: flag) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in self?.finishRecording(for: identifier, successfully: false) }
    }
}

extension VoiceNoteRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identifier else { return }
            self.stopPlayback()
            if !flag { self.error = self.text("bug_voice_playback_failed") }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identifier else { return }
            self.stopPlayback()
            self.error = self.text("bug_voice_playback_failed")
        }
    }
}

#endif
