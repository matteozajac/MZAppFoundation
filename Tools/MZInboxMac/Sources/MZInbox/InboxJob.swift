import Foundation

struct InboxJob: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let reportID: String?
    let title: String
    let app: String?
    let bundleIdentifier: String?
    let status: String
    let receivedAt: String?
    let updatedAt: String?
    let error: String?
    let statusSyncError: String?
    let jobDirectory: String?
    let resultPath: String?
    let threadID: String?
    let worktreePath: String?

    var appName: String { app ?? bundleIdentifier ?? "Unknown app" }
    var statusTitle: String {
        switch status {
        case "receiving": "Downloading"
        case "queued": "Waiting for agent"
        case "running", "investigating": "Investigating"
        case "preparing", "inspecting": "Preparing report"
        case "transcribing": "Transcribing voice note"
        case "preparing_fix": "Preparing a fix"
        case "fix_ready": "Fix ready"
        case "completed": "Result ready"
        case "waiting_for_route": "Choose a project"
        case "waiting_for_description": "A description is needed"
        case "waiting_transcription", "waiting_for_transcription": "Voice transcription needs attention"
        case "interrupted": "Interrupted"
        case "failed": "Needs attention"
        case "rate_limited": "Waiting for Codex usage reset"
        case "rejected": "Report could not be accepted"
        case "duplicate": "Already received"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    var symbol: String {
        switch status {
        case "completed", "fix_ready": "checkmark.circle"
        case "running", "investigating", "preparing", "inspecting", "transcribing", "preparing_fix": "gearshape.2"
        case "failed", "interrupted", "waiting_transcription", "waiting_for_transcription": "exclamationmark.circle"
        case "waiting_for_route": "folder.badge.questionmark"
        case "rate_limited": "clock"
        case "rejected", "waiting_for_description": "exclamationmark.circle"
        default: "tray.and.arrow.down"
        }
    }
    var canRetry: Bool {
        ["failed", "interrupted", "waiting_transcription", "waiting_for_transcription", "rate_limited"].contains(status)
    }
    var receivedDate: Date? {
        guard let receivedAt else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: receivedAt) ?? ISO8601DateFormatter().date(from: receivedAt)
    }
}

struct QueueSnapshot: Decodable, Sendable {
    var jobs: [InboxJob] = []
    var lastScanAt: String?
    var workerError: String?
}
