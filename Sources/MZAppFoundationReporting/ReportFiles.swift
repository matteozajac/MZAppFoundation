#if os(iOS)
import Foundation

struct ReportFiles: Sendable {
    let root: URL

    init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("BugReporter", isDirectory: true)) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    func directory() throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func remove(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func clearAbandoned() {
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            remove(url)
        }
    }
}

#endif
