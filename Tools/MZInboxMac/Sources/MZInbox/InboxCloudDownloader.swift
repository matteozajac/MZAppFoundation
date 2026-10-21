import Foundation

/// File Provider metadata can block inside Foundation. Keep it off the actor
/// that serves configuration writes, queue snapshots, and pause/resume controls.
actor InboxCloudDownloader {
    func requestDownloads(inboxPath: String) -> Int {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isDirectoryKey]
        let inbox = URL(fileURLWithPath: inboxPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: inbox, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
        ) else { return 0 }
        var downloads = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? file.resourceValues(forKeys: keys), values.isDirectory != true,
                  values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current else { continue }
            if (try? FileManager.default.startDownloadingUbiquitousItem(at: file)) != nil { downloads += 1 }
        }
        return downloads
    }
}
