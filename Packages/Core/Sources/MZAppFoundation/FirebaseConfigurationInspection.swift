import Foundation

/// Inspects Apple's client plist without importing or starting Firebase.
public struct FirebaseConfigurationInspection: Equatable, Sendable {
    public let state: ProviderConfigurationState
    public let details: [ProviderDetail]
    public let explanation: String

    public static func inspect(bundleIdentifier: String, path: String?) -> Self {
        guard let path else {
            return Self(state: .missing, details: [.init("file", label: "Configuration file", value: "GoogleService-Info.plist missing")],
                        explanation: "No Apple Firebase configuration file was supplied. Add this app's GoogleService-Info.plist when using Firebase.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return Self(state: .missing, details: [.init("file", label: "Configuration file", value: "Supplied file missing")],
                        explanation: "The supplied Firebase configuration file does not exist in this build.")
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return Self(state: .invalid, details: [.init("file", label: "Configuration file", value: "Unreadable or invalid plist")],
                        explanation: "The Firebase configuration file could not be read as a property list.")
        }
        // Explicit allowlist: API_KEY, client secrets and arbitrary plist fields never enter diagnostics.
        let fields = [("PROJECT_ID", "Project ID"), ("GOOGLE_APP_ID", "Google app ID"),
                      ("BUNDLE_ID", "Configured bundle ID"), ("GCM_SENDER_ID", "Sender ID"),
                      ("STORAGE_BUCKET", "Storage bucket")]
        var details = [ProviderDetail("file", label: "Configuration file", value: "Present")]
        for (key, label) in fields {
            if let value = plist[key] as? String, !value.isEmpty {
                details.append(.init(key, label: label, value: value))
            }
        }
        let required = ["PROJECT_ID", "GOOGLE_APP_ID", "GCM_SENDER_ID", "API_KEY"]
        let valid = required.allSatisfy { (plist[$0] as? String)?.isEmpty == false }
            && plist["BUNDLE_ID"] as? String == bundleIdentifier
        return Self(state: valid ? .configured : .invalid, details: details,
                    explanation: valid
                        ? "Client identifiers match this app. This does not verify Analytics linking or event ingestion."
                        : "Required Firebase fields are missing, or BUNDLE_ID does not match this app.")
    }
}
