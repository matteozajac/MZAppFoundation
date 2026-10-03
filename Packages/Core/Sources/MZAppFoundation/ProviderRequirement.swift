import Foundation

public enum FoundationPlatform: String, CaseIterable, Codable, Sendable {
    case iOS, visionOS, macOS

    public static var current: Self {
        #if os(visionOS)
        .visionOS
        #elseif os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }
}

/// Rules are applied in order, so an app can declare defaults followed by scoped exceptions.
public struct ProviderRequirement: Equatable, Codable, Sendable {
    public let provider: FoundationProvider
    public let expectation: ProviderExpectation
    public let environments: Set<AppEnvironment>
    public let platforms: Set<FoundationPlatform>

    public init(_ provider: FoundationProvider, expectation: ProviderExpectation,
                environments: Set<AppEnvironment> = [.local, .internalTesting, .production],
                platforms: Set<FoundationPlatform> = Set(FoundationPlatform.allCases)) {
        self.provider = provider; self.expectation = expectation
        self.environments = environments; self.platforms = platforms
    }

    public func applies(environment: AppEnvironment, platform: FoundationPlatform) -> Bool {
        environments.contains(environment) && platforms.contains(platform)
    }
}
