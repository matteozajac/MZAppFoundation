import Foundation
import MZAppFoundation

public struct LiveConfiguration: Equatable, Sendable {
    public let revenueCatPublicKey: String?
    public let sentryDSN: String?
    public let revenueCatProject: ProviderProjectIdentity
    public let sentryProject: ProviderProjectIdentity
    public init(revenueCatPublicKey: String? = nil, sentryDSN: String? = nil,
                revenueCatProject: ProviderProjectIdentity = .init(), sentryProject: ProviderProjectIdentity = .init()) {
        self.revenueCatPublicKey = revenueCatPublicKey
        self.sentryDSN = sentryDSN
        self.revenueCatProject = revenueCatProject
        self.sentryProject = sentryProject
    }
}
