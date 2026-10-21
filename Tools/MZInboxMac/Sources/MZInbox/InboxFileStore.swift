import Foundation

actor InboxFileStore {
    func loadConfiguration() throws -> InboxConfiguration {
        let data = try Data(contentsOf: InboxConfiguration.configURL)
        return try JSONDecoder().decode(InboxConfiguration.self, from: data)
    }

    func saveConfiguration(_ configuration: InboxConfiguration, expectedRoutes: [AppRoute]? = nil) throws {
        guard configuration.schemaVersion == 1 else {
            throw InboxError.message("This configuration uses an unsupported version.")
        }
        for path in [configuration.inboxPath, configuration.statusPath, configuration.statePath] {
            guard path.hasPrefix("/") else { throw InboxError.message("Choose an absolute folder path.") }
        }
        guard configuration.codexPath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: configuration.codexPath) else {
            throw InboxError.message("Choose an installed Codex executable.")
        }
        if let model = configuration.whisperModel, !FileManager.default.fileExists(atPath: model) {
            throw InboxError.message("The selected Whisper model does not exist.")
        }
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(configuration)
        let values = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        var existing: [String: Any] = [:]
        if let data = try? Data(contentsOf: InboxConfiguration.configURL) {
            if let expectedRoutes, try JSONDecoder().decode(InboxConfiguration.self, from: data).routes != expectedRoutes {
                throw InboxError.message("App projects changed while Settings was open. Reload Settings before saving.")
            }
            existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } else if let expectedRoutes, !expectedRoutes.isEmpty {
            throw InboxError.message("App projects changed while Settings was open. Reload Settings before saving.")
        }
        existing.merge(values) { _, new in new }
        if configuration.whisperModel == nil { existing.removeValue(forKey: "whisperModel") }
        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: InboxConfiguration.applicationSupport, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // The worker creates shared folders. File Provider operations can block;
        // configuration writes must remain independent of the cloud volume.
        try FileManager.default.createDirectory(atPath: configuration.statePath, withIntermediateDirectories: true)
        try data.write(to: InboxConfiguration.configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: InboxConfiguration.configURL.path)
    }

    func snapshot(configuration: InboxConfiguration) throws -> QueueSnapshot {
        let path = URL(fileURLWithPath: configuration.statePath).appendingPathComponent("queue.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return QueueSnapshot() }
        return try JSONDecoder().decode(QueueSnapshot.self, from: Data(contentsOf: path))
    }

    func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

enum InboxError: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
