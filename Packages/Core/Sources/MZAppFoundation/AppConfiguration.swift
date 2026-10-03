import Foundation

public enum AppEnvironment: String, Codable, Sendable {
    case local, internalTesting, production
}

public struct DeliveryPreferences: Equatable, Codable, Sendable {
    public var analytics: Bool
    public var diagnostics: Bool

    public init(analytics: Bool = true, diagnostics: Bool = true) {
        self.analytics = analytics
        self.diagnostics = diagnostics
    }
}

public struct AppConfiguration: Equatable, Sendable {
    public let bundleIdentifier: String
    public let urlScheme: String
    public let developerLinkHost: String
    public let environment: AppEnvironment
    public let version: String
    public let build: String
    public let preferences: DeliveryPreferences
    public var release: String { "\(bundleIdentifier)@\(version)+\(build)" }

    public init(bundleIdentifier: String, urlScheme: String, environment: AppEnvironment,
                version: String = "0", build: String = "0", preferences: DeliveryPreferences = .init(),
                developerLinkHost: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.urlScheme = urlScheme
        self.developerLinkHost = (developerLinkHost ?? bundleIdentifier).lowercased()
        self.environment = environment
        self.version = version
        self.build = build
        self.preferences = preferences
    }
}

public enum RuntimeSafety {
    /// App build flags are deliberately not assumed to propagate into Swift packages.
    public static func permitsRemote(environment: AppEnvironment) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let process = ProcessInfo.processInfo
        return environment != .local
            && process.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
            && process.environment["XCTestConfigurationFilePath"] == nil
            && process.environment["XCTestBundlePath"] == nil
            && !process.arguments.contains("--ui-testing")
            && NSClassFromString("XCTestCase") == nil
        #endif
    }
}
