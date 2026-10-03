import Foundation

/// One short URL contract for every platform: `<app-scheme>://developer/enable` or `/disable`.
public enum DeveloperDeepLink {
    /// The former shared scheme is reserved and no longer accepted. Register the app's unique scheme.
    public static let scheme = "mzappfoundation"

    public enum Action: String, Sendable { case enable, disable }
    public enum Format: String, Sendable {
        case shared = "Shared scheme", appSpecific = "App-specific scheme", legacy = "Legacy route"
    }
    public enum RejectionReason: String, Sendable {
        case malformedURL = "Malformed URL"
        case invalidConfiguration = "Invalid app URL scheme"
        case unsupportedScheme = "Unrecognized URL scheme"
        case credentials = "Credentials are not allowed"
        case port = "Ports are not allowed"
        case query = "Query parameters are not allowed"
        case fragment = "Fragments are not allowed"
        case encodedComponents = "Encoded host or route is not allowed"
        case unexpectedHost = "Expected the developer host"
        case unsupportedRoute = "Unsupported developer route"
    }

    public static func url(for action: Action, scheme: String) -> URL? {
        guard validScheme(scheme) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme.lowercased()
        parts.host = "developer"
        parts.path = "/" + action.rawValue
        return parts.url
    }

    /// Source-compatible with 0.5.0. App identity is now supplied by the scheme; the host is unused.
    public static func url(for action: Action, host: String, scheme: String = scheme) -> URL? {
        url(for: action, scheme: scheme)
    }

    public static func action(for url: URL, scheme: String) -> Action? {
        inspect(url.absoluteString, scheme: scheme).action
    }

    /// Source-compatible with 0.5.0. Supply the app-specific scheme through `legacyScheme`.
    public static func action(for url: URL, host: String, legacyScheme: String? = nil) -> Action? {
        inspect(url.absoluteString, host: host, legacyScheme: legacyScheme).action
    }

    /// Dry-run only. The result never copies input text, so rejected URLs cannot leak credentials.
    public static func inspect(_ raw: String, scheme: String) -> DeveloperDeepLinkInspection {
        func reject(_ reason: RejectionReason) -> DeveloperDeepLinkInspection {
            .init(action: nil, format: nil, rejectionReason: reason)
        }
        guard validScheme(scheme) else { return reject(.invalidConfiguration) }
        guard !raw.isEmpty, raw.utf8.count <= 4_096,
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: raw), parts.url != nil, parts.scheme != nil else { return reject(.malformedURL) }
        guard parts.user == nil, parts.password == nil else { return reject(.credentials) }
        guard parts.port == nil else { return reject(.port) }
        guard parts.query == nil else { return reject(.query) }
        guard parts.fragment == nil else { return reject(.fragment) }
        guard parts.scheme?.lowercased() == scheme.lowercased() else { return reject(.unsupportedScheme) }
        guard !(parts.percentEncodedHost?.contains("%") ?? false), !parts.percentEncodedPath.contains("%") else {
            return reject(.encodedComponents)
        }
        guard parts.percentEncodedHost?.lowercased() == "developer" else { return reject(.unexpectedHost) }
        switch parts.percentEncodedPath {
        case "/enable": return .init(action: .enable, format: .appSpecific, rejectionReason: nil)
        case "/disable": return .init(action: .disable, format: .appSpecific, rejectionReason: nil)
        default: return reject(.unsupportedRoute)
        }
    }

    /// Source-compatible with 0.5.0. Long URLs with an app or bundle-ID host are no longer accepted.
    public static func inspect(_ raw: String, host: String, legacyScheme: String? = nil) -> DeveloperDeepLinkInspection {
        inspect(raw, scheme: legacyScheme ?? scheme)
    }

    private static func validScheme(_ scheme: String) -> Bool {
        guard scheme.lowercased() != self.scheme,
              let first = scheme.utf8.first, (65...90).contains(first) || (97...122).contains(first) else { return false }
        return scheme.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [43, 45, 46].contains($0)
        }
    }
}

public struct DeveloperDeepLinkInspection: Equatable, Sendable {
    public let action: DeveloperDeepLink.Action?
    public let format: DeveloperDeepLink.Format?
    public let rejectionReason: DeveloperDeepLink.RejectionReason?
    public var accepted: Bool { action != nil && rejectionReason == nil }
}
