import Foundation

struct InboxConfiguration: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var inboxPath: String
    var statusPath: String
    var statePath: String
    var codexPath: String
    var whisperModel: String?
    var pollSeconds = 5
    var paused = false
    var routes: [AppRoute] = []

    static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MZ Inbox", isDirectory: true)
    }

    static var configURL: URL { applicationSupport.appendingPathComponent("config.json") }

    static var defaults: Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/MZ Inbox")
        return Self(
            inboxPath: cloud.appendingPathComponent("Incoming").path,
            statusPath: cloud.appendingPathComponent("Status").path,
            statePath: applicationSupport.appendingPathComponent("state").path,
            codexPath: "/opt/homebrew/bin/codex"
        )
    }

    init(
        inboxPath: String, statusPath: String, statePath: String, codexPath: String,
        whisperModel: String? = nil
    ) {
        self.inboxPath = inboxPath
        self.statusPath = statusPath
        self.statePath = statePath
        self.codexPath = codexPath
        self.whisperModel = whisperModel
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        inboxPath = try values.decode(String.self, forKey: .inboxPath)
        statusPath = try values.decode(String.self, forKey: .statusPath)
        statePath = try values.decode(String.self, forKey: .statePath)
        codexPath = try values.decode(String.self, forKey: .codexPath)
        whisperModel = try values.decodeIfPresent(String.self, forKey: .whisperModel)
        pollSeconds = try values.decodeIfPresent(Int.self, forKey: .pollSeconds) ?? 5
        paused = try values.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        routes = try values.decodeIfPresent([AppRoute].self, forKey: .routes) ?? []
    }
}
