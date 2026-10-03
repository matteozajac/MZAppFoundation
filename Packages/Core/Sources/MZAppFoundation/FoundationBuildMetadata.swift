import Foundation

/// Build evidence, independent of provider runtime versions. Unstamped fields stay absent.
public struct FoundationBuildMetadata: Equatable, Codable, Sendable {
    public var appRevision: String?
    public var foundationRevision: String?
    public var foundationVersion: String
    public var buildChannel: String?
    public var buildDate: Date?
    public var resolvedPackageVersions: [String: String]
    public var appWorkingTreeModified: Bool?
    public var foundationWorkingTreeModified: Bool?
    public var provenance: String

    public init(appRevision: String? = nil, foundationRevision: String? = nil,
                foundationVersion: String = FoundationVersion.current, buildChannel: String? = nil,
                buildDate: Date? = nil, resolvedPackageVersions: [String: String] = [:],
                appWorkingTreeModified: Bool? = nil, foundationWorkingTreeModified: Bool? = nil,
                provenance: String = "App-supplied build metadata") {
        self.appRevision = appRevision; self.foundationRevision = foundationRevision
        self.foundationVersion = foundationVersion; self.buildChannel = buildChannel; self.buildDate = buildDate
        self.resolvedPackageVersions = resolvedPackageVersions
        self.appWorkingTreeModified = appWorkingTreeModified
        self.foundationWorkingTreeModified = foundationWorkingTreeModified
        self.provenance = provenance
    }

    /// The build script adds a standalone resource after compilation, without rewriting Info.plist.
    public static func current(bundle: Bundle = .main) -> Self {
        if let url = bundle.url(forResource: "MZFoundationBuildMetadata", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let stamp = try? PropertyListDecoder().decode(Self.self, from: data) { return stamp }
        return .init(resolvedPackageVersions: FoundationVersion.resolvedPackageVersions,
                     provenance: "Library Package.resolved snapshot; app build is not stamped")
    }
}
