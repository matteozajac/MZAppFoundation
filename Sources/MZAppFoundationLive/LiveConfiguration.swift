import Foundation

public struct LiveConfiguration: Equatable, Sendable {
    public let revenueCatPublicKey: String?
    public let sentryDSN: String?
    public init(revenueCatPublicKey: String? = nil, sentryDSN: String? = nil) {
        self.revenueCatPublicKey = revenueCatPublicKey
        self.sentryDSN = sentryDSN
    }
}

public enum BootstrapFailure: Error { case configurationConflict, invalidRevenueCatKey, invalidSentryDSN, invalidFirebaseConfiguration }
