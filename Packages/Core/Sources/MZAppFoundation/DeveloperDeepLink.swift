import Foundation

/// One URL contract for every app and platform. Hosts identify individual apps.
public enum DeveloperDeepLink {
    public static let scheme = "mzappfoundation"

    public enum Action: String, Sendable { case enable, disable }
    public enum Format: String, Sendable {
        case shared = "Shared scheme", appSpecific = "App-specific scheme", legacy = "Legacy route"
    }
    public enum RejectionReason: String, Sendable {
        case malformedURL = "Malformed URL"
        case invalidConfiguration = "Invalid expected host or app scheme"
        case unsupportedScheme = "Unrecognized URL scheme"
        case credentials = "Credentials are not allowed"
        case port = "Ports are not allowed"
        case query = "Query parameters are not allowed"
        case fragment = "Fragments are not allowed"
        case encodedComponents = "Encoded host or route is not allowed"
        case unexpectedHost = "URL belongs to another app host"
        case unsupportedRoute = "Unsupported developer route"
    }

    public static func url(for action: Action, host: String, scheme: String = scheme) -> URL? {
        guard validHost(host), validScheme(scheme) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = "/developer/" + action.rawValue
        return parts.url
    }

    public static func action(for url: URL, host: String, legacyScheme: String? = nil) -> Action? {
        inspect(url.absoluteString, host: host, legacyScheme: legacyScheme).action
    }

    /// Dry-run only. The result never copies input text, so rejected URLs cannot leak credentials.
    public static func inspect(_ raw: String, host: String, legacyScheme: String? = nil) -> DeveloperDeepLinkInspection {
        func reject(_ reason: RejectionReason) -> DeveloperDeepLinkInspection {
            .init(action: nil, format: nil, rejectionReason: reason)
        }
        guard validHost(host), legacyScheme.map(validScheme) != false else { return reject(.invalidConfiguration) }
        guard !raw.isEmpty, raw.utf8.count <= 4_096,
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: raw), parts.url != nil, parts.scheme != nil else { return reject(.malformedURL) }
        guard parts.user == nil, parts.password == nil else { return reject(.credentials) }
        guard parts.port == nil else { return reject(.port) }
        guard parts.query == nil else { return reject(.query) }
        guard parts.fragment == nil else { return reject(.fragment) }
        let isSharedScheme = parts.scheme?.lowercased() == scheme
        let isAppScheme = legacyScheme != nil && parts.scheme?.lowercased() == legacyScheme?.lowercased()
        guard isSharedScheme || isAppScheme else { return reject(.unsupportedScheme) }
        guard !(parts.percentEncodedHost?.contains("%") ?? false), !parts.percentEncodedPath.contains("%") else {
            return reject(.encodedComponents)
        }
        let route: String
        let format: Format
        if parts.percentEncodedHost?.lowercased() == host.lowercased() {
            route = parts.percentEncodedPath
            format = isSharedScheme ? .shared : .appSpecific
        } else if !isSharedScheme, isAppScheme, parts.percentEncodedHost?.lowercased() == "developer" {
        // Transitional compatibility for existing <app-scheme>://developer/enable links.
            route = "/developer" + parts.percentEncodedPath
            format = .legacy
        } else { return reject(.unexpectedHost) }
        switch route {
        case "/developer/enable": return .init(action: .enable, format: format, rejectionReason: nil)
        case "/developer/disable": return .init(action: .disable, format: format, rejectionReason: nil)
        default: return reject(.unsupportedRoute)
        }
    }

    private static func validHost(_ host: String) -> Bool {
        func alphanumeric(_ character: UInt8) -> Bool {
            (65...90).contains(character) || (97...122).contains(character) || (48...57).contains(character)
        }
        return !host.isEmpty && host.utf8.count <= 253 && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard let first = label.utf8.first, let last = label.utf8.last,
                  label.utf8.count <= 63, alphanumeric(first), alphanumeric(last) else { return false }
            return label.utf8.allSatisfy { alphanumeric($0) || $0 == 45 }
        }
    }

    private static func validScheme(_ scheme: String) -> Bool {
        guard let first = scheme.utf8.first, (65...90).contains(first) || (97...122).contains(first) else { return false }
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
