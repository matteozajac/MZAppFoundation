import Foundation
import Testing
@testable import MZAppFoundation

struct FoundationBuildMetadataTests {
    @Test func unstampedBuildDoesNotPretendToHaveARevisionOrDate() {
        let result = FoundationBuildMetadata.current(bundle: Bundle(for: FoundationBuildMetadataBundleMarker.self))
        #expect(result.foundationVersion == FoundationVersion.current)
        #expect(result.appRevision == nil && result.foundationRevision == nil && result.buildDate == nil)
        #expect(result.provenance.contains("snapshot"))
    }
    @Test func safeBuildStampRoundTripsWithoutLosingDirtyEvidence() throws {
        let supplied = FoundationBuildMetadata(appRevision: String(repeating: "a", count: 40),
                                              foundationRevision: String(repeating: "b", count: 40),
                                              buildChannel: "Internal", buildDate: Date(timeIntervalSince1970: 123),
                                              resolvedPackageVersions: ["pulse": "5.2.1"],
                                              appWorkingTreeModified: true, foundationWorkingTreeModified: false)
        let data = try PropertyListEncoder().encode(supplied)
        #expect(try PropertyListDecoder().decode(FoundationBuildMetadata.self, from: data) == supplied)
    }
}

private final class FoundationBuildMetadataBundleMarker: NSObject {}
