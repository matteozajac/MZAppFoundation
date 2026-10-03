import Foundation
import Observation
import Synchronization

private struct DeveloperCaptureState: Sendable {
    var enabled = false
    var deadline: ContinuousClock.Instant?
}

@MainActor @Observable public final class DeveloperOptions {
    public enum ActivationSource: String, Sendable {
        case appDefault = "default", saved, migrated, link, manual, session
    }
    /// Shared spelling, scoped to the supplied UserDefaults store. No cross-app access is implied.
    public static let preferenceKey = "mzappfoundation.developer.enabled"
    public static let consoleSceneID = "mzappfoundation.console"
    public private(set) var isEnabled: Bool
    public private(set) var activationSource: ActivationSource
    public private(set) var expiresAt: Date?
    public private(set) var consoleRequested = false
    /// Emits only library-owned activity codes. It never includes a URL or preference contents.
    @ObservationIgnored public var onActivity: (@MainActor (String) -> Void)?
    private nonisolated let capture = Mutex(DeveloperCaptureState())
    public nonisolated var allowsNetworkCapture: Bool {
        capture.withLock { state in
            state.enabled && (state.deadline.map { ContinuousClock.now < $0 } ?? true)
        }
    }
    private let scheme: String
    public let linkHost: String
    private let defaults: UserDefaults
    private var didLaunch = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var expiryID: UUID?

    public init(configuration: AppConfiguration, defaults: UserDefaults = .standard,
                legacyPreferenceKeys: [String] = []) {
        self.scheme = configuration.urlScheme.lowercased()
        self.linkHost = configuration.developerLinkHost
        self.defaults = defaults
        let legacy = ([configuration.bundleIdentifier + ".developer.enabled"] + legacyPreferenceKeys)
            .lazy.compactMap { defaults.object(forKey: $0) as? Bool }.first
        if let persisted = defaults.object(forKey: Self.preferenceKey) as? Bool {
            self.isEnabled = persisted
            self.activationSource = .saved
        } else if let legacy {
            self.isEnabled = legacy
            self.activationSource = .migrated
            defaults.set(legacy, forKey: Self.preferenceKey)
        } else {
            self.isEnabled = configuration.environment != .production
            self.activationSource = .appDefault
        }
        capture.withLock { $0.enabled = isEnabled }
    }
    public func setEnabled(_ enabled: Bool) {
        persist(enabled, source: .manual)
    }

    private func persist(_ enabled: Bool, source: ActivationSource) {
        cancelExpiry()
        activationSource = source
        apply(enabled)
        defaults.set(enabled, forKey: Self.preferenceKey)
        onActivity?(enabled ? "developer.access.enabled" : "developer.access.disabled")
    }

    private func apply(_ enabled: Bool) {
        isEnabled = enabled
        capture.withLock { $0.enabled = enabled; $0.deadline = nil }
        if !enabled { consoleRequested = false }
    }

    /// Replaces persistent access with access that ends when this app process exits.
    public func enableUntilAppCloses() {
        beginSession()
        onActivity?("developer.access.session")
    }

    /// A monotonic task and capture deadline revoke access. The date is for display only.
    @discardableResult public func enable(for duration: TimeInterval) -> Bool {
        guard duration.isFinite, duration > 0, duration <= 365 * 24 * 60 * 60 else { return false }
        beginSession()
        expiresAt = Date().addingTimeInterval(duration)
        capture.withLock { $0.deadline = ContinuousClock.now.advanced(by: .seconds(duration)) }
        let id = UUID()
        expiryID = id
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            guard !Task.isCancelled, let self, self.expiryID == id else { return }
            self.expireSession()
        }
        onActivity?("developer.access.timed")
        return true
    }

    public func refreshExpiration() {
        let elapsed = capture.withLock { $0.deadline.map { ContinuousClock.now >= $0 } ?? false }
        if elapsed { expireSession() }
    }

    private func beginSession() {
        cancelExpiry()
        // An explicit false also overrides development defaults on the next launch.
        defaults.set(false, forKey: Self.preferenceKey)
        activationSource = .session
        apply(true)
    }

    private func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        expiryID = nil
        expiresAt = nil
    }

    private func expireSession() {
        cancelExpiry()
        apply(false)
        onActivity?("developer.access.expired")
    }
    @discardableResult public func handle(_ url: URL) -> Bool {
        guard let action = DeveloperDeepLink.action(for: url, host: linkHost, legacyScheme: scheme) else {
            onActivity?("developer.link.rejected")
            return false
        }
        persist(action == .enable, source: .link)
        return true
    }
    public func requestConsole() { if isEnabled { consoleRequested = true } }
    public func dismissConsole() { consoleRequested = false }
    public func launchSpatialConsole() {
        guard !didLaunch else { return }
        didLaunch = true
        requestConsole()
    }
    deinit { expiryTask?.cancel() }
}
