import Foundation
import MZAppFoundation
import Pulse
import Synchronization

/// Explicitly instrumented URLSession access; it never changes global URLSession behavior.
@MainActor public final class InstrumentedSession {
    private let options: DeveloperOptions
    private let proxy: URLSessionProxy

    public init(options: DeveloperOptions, configuration: URLSessionConfiguration = .default,
                redaction: RedactionPolicy = .init()) {
        self.options = options
        let logger = NetworkLogger { config in
            config.sensitiveHeaders = ["Authorization", "Cookie", "Set-Cookie", "X-Firebase-AppCheck"]
            config.willHandleEvent = { event in
                guard options.allowsNetworkCapture else { return nil }
                switch event {
                case .networkTaskCreated(var value):
                    value.originalRequest = Self.sanitize(value.originalRequest, redaction: redaction)
                    value.currentRequest = value.currentRequest.map { Self.sanitize($0, redaction: redaction) }
                    value.taskDescription = nil
                    return .networkTaskCreated(value)
                case .networkTaskCompleted(var value):
                    value.originalRequest = Self.sanitize(value.originalRequest, redaction: redaction)
                    value.currentRequest = value.currentRequest.map { Self.sanitize($0, redaction: redaction) }
                    value.requestBody = nil; value.responseBody = nil
                    let headers = value.response?.headers?.filter {
                        !RedactionPolicy.isSensitive($0.key) && !redaction.additionalSensitiveKeys.contains($0.key.lowercased())
                    }
                    value.response?.headers = headers
                    value.error = nil; value.metrics = nil; value.taskDescription = nil
                    return .networkTaskCompleted(value)
                case .networkTaskProgressUpdated(var value):
                    value.url = Self.sanitizeURL(value.url)
                    return .networkTaskProgressUpdated(value)
                case .messageStored: return nil
                }
            }
        }
        var proxyOptions = URLSessionProxy.Options()
        proxyOptions.isMockingEnabled = false
        proxy = URLSessionProxy(configuration: configuration, logger: logger, options: proxyOptions)
    }
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await proxy.data(for: request)
    }
    nonisolated private static func sanitize(_ request: NetworkLogger.Request, redaction: RedactionPolicy) -> NetworkLogger.Request {
        var request = request
        request.url = sanitizeURL(request.url)
        request.headers = request.headers?.filter {
            !RedactionPolicy.isSensitive($0.key) && !redaction.additionalSensitiveKeys.contains($0.key.lowercased())
        }
        return request
    }
    nonisolated private static func sanitizeURL(_ url: URL?) -> URL? {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.user = nil; parts.password = nil; parts.fragment = nil
        // Query values are omitted entirely; token names vary across backends.
        parts.query = nil
        return parts.url
    }
}
