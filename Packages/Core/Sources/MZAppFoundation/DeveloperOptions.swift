import Foundation
import Observation
import Synchronization

@MainActor @Observable public final class DeveloperOptions {
    public private(set) var isEnabled: Bool
    public private(set) var consoleRequested = false
    private nonisolated let capture = Mutex(false)
    public nonisolated var allowsNetworkCapture: Bool { capture.withLock { $0 } }
    private let scheme: String
    private let key: String
    private let defaults: UserDefaults
    private var didLaunch = false

    public init(configuration: AppConfiguration, defaults: UserDefaults = .standard) {
        self.scheme = configuration.urlScheme.lowercased()
        self.key = configuration.bundleIdentifier + ".developer.enabled"
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: key) as? Bool ?? (configuration.environment != .production)
        capture.withLock { $0 = isEnabled }
    }
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        capture.withLock { $0 = enabled }
        defaults.set(enabled, forKey: key)
        if !enabled { consoleRequested = false }
    }
    @discardableResult public func handle(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme, parts.host?.lowercased() == "developer",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return false }
        switch parts.percentEncodedPath {
        case "/enable": setEnabled(true)
        case "/disable": setEnabled(false)
        default: return false
        }
        return true
    }
    public func requestConsole() { if isEnabled { consoleRequested = true } }
    public func dismissConsole() { consoleRequested = false }
    public func launchSpatialConsole() {
        guard !didLaunch else { return }
        didLaunch = true
        requestConsole()
    }
}
