#if os(iOS)
import Foundation

/// File coordination provides a standard ZIP without an additional dependency.
/// Staging and compression run on this actor, away from the report's main actor.
actor ReportArchive {
    func create(files: [URL], in output: URL, name: String) throws -> URL {
        try Self.write(files: files, in: output, name: name)
    }

    nonisolated static func name(prefix: String, id: UUID) -> String {
        let safe = prefix.lowercased().unicodeScalars.filter {
            (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "-"
        }
        let cleaned = String(String.UnicodeScalarView(safe)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(cleaned.isEmpty ? "bug-report" : String(cleaned.prefix(64)))-\(id.uuidString.lowercased())"
    }

    nonisolated private static func write(files: [URL], in output: URL, name: String) throws -> URL {
        let manager = FileManager.default
        let staging = output.appendingPathComponent(name, isDirectory: true)
        let archive = output.appendingPathComponent(name + ".zip")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        var names = Set<String>()
        for file in files {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  names.insert(file.lastPathComponent.lowercased()).inserted else {
                throw failure()
            }
            try manager.copyItem(at: file, to: staging.appendingPathComponent(file.lastPathComponent))
        }
        var coordinationError: NSError?
        var result: Result<URL, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinationError) { temporaryZIP in
            result = Result {
                // The coordinator unlinks its snapshot when this block returns.
                try manager.moveItem(at: temporaryZIP, to: archive)
                return archive
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw failure() }
        return try result.get()
    }

    nonisolated private static func failure() -> NSError {
        NSError(domain: "BugReporter.Archive", code: 1, userInfo: [
            NSLocalizedDescriptionKey: BugReportStrings.text("bug_zip_failed")
        ])
    }
}

#endif
