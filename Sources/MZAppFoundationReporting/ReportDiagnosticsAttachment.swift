#if os(iOS)
import Foundation
import CoreFoundation

/// Reporting stays independent from the app foundation. Hosts provide its redacted JSON snapshot.
enum ReportDiagnosticsCapture {
    case notProvided, available(Data), unavailable

    @MainActor static func capture(_ provider: (@MainActor () throws -> Data)?) -> Self {
        guard let provider else { return .notProvided }
        do { return .available(try ReportDiagnosticsAttachment.validated(provider())) }
        catch { return .unavailable }
    }
}

public enum ReportDiagnosticsAttachment {
    public static let maximumBytes = 1_048_576

    /// Bounds, expected format, and a second forbidden-field check protect ZIP attachment intake.
    /// The supplying host must also exclude private values from permitted project/build fields.
    public static func validated(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumBytes,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["format"] as? String == "mzappfoundation-diagnostics",
              let version = root["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == NSNumber(value: 1) else { throw ValidationError.invalid }
        var values = 0
        try validate(root, depth: 0, values: &values)
        return data
    }

    private static func validate(_ value: Any, depth: Int, values: inout Int) throws {
        values += 1
        guard depth <= 16, values <= 20_000 else { throw ValidationError.invalid }
        if let object = value as? [String: Any] {
            guard object.count <= 128 else { throw ValidationError.invalid }
            for (key, child) in object {
                let lower = key.lowercased().replacingOccurrences(of: "_", with: "")
                guard key.count <= 128,
                      !["token", "password", "secret", "authorization", "cookie", "receipt", "transaction",
                        "email", "phone", "userid", "prompt", "transcript", "payload", "apikey", "dsn"].contains(where: lower.contains)
                else { throw ValidationError.invalid }
                try validate(child, depth: depth + 1, values: &values)
            }
        } else if let array = value as? [Any] {
            guard array.count <= 1_000 else { throw ValidationError.invalid }
            for child in array { try validate(child, depth: depth + 1, values: &values) }
        } else if let text = value as? String {
            guard text.count <= 2_048 else { throw ValidationError.invalid }
        }
    }

    public enum ValidationError: Error, Sendable { case invalid }
}
#endif
