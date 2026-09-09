import Foundation
import MZAppFoundation
import Sentry

@MainActor final class SentryDiagnostics: DiagnosticsEngine {
    let delivery = DeliveryKind.remote
    private let configuration: AppConfiguration
    private let dsn: String
    private var gate: SentryTransportGate?
    private let cache: URL

    init(dsn: String, configuration: AppConfiguration) throws {
        guard let url = URLComponents(string: dsn), url.scheme == "https", url.host != nil,
              url.user?.isEmpty == false, url.password == nil, !url.path.isEmpty else {
            throw BootstrapFailure.invalidSentryDSN
        }
        guard !SentrySDK.isEnabled else { throw BootstrapFailure.configurationConflict }
        self.dsn = dsn; self.configuration = configuration
        cache = URL.cachesDirectory.appending(path: configuration.bundleIdentifier + ".sentry")
    }
    func setEnabled(_ enabled: Bool) {
        let permitted = enabled && RuntimeSafety.permitsRemote(environment: configuration.environment)
        guard permitted else {
            if let gate {
                gate.revoke()
                SentrySDK.close()
                self.gate = nil
            }
            try? FileManager.default.removeItem(at: cache)
            return
        }
        guard gate == nil else { return }
        let gate = SentryTransportGate()
        let options = Options()
        options.dsn = dsn
        options.releaseName = configuration.release
        options.environment = configuration.environment.rawValue
        options.dist = configuration.build
        options.urlSessionDelegate = gate
        options.cacheDirectoryPath = cache.path
        options.sendDefaultPii = false
        options.enableCrashHandler = true
        options.enableAutoSessionTracking = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableAppHangTracking = false
        options.enableWatchdogTerminationTracking = false
        options.enableMetricKit = false
        options.enableSwizzling = false
        options.enableAutoPerformanceTracing = false
        options.enableNetworkTracking = false
        options.enableCaptureFailedRequests = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableLogs = false
        options.sendClientReports = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.tracesSampleRate = 0
        #if os(iOS)
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        #endif
        options.shutdownTimeInterval = 0
        options.beforeSend = { event in
            guard gate.allowsDelivery else { return nil }
            event.user = nil; event.request = nil; event.extra = nil
            return event
        }
        self.gate = gate
        SentrySDK.start(options: options)
        SentrySDK.setUser(nil)
    }
    func record(_ issue: DiagnosticIssue) -> EngineResult {
        guard gate?.allowsDelivery == true else { return .ignored }
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: issue.code)
        event.tags = ["issue_code": issue.code, "issue_category": issue.category]
        SentrySDK.capture(event: event)
        return .recorded
    }
    func breadcrumb(_ event: TelemetryEvent) {
        guard gate?.allowsDelivery == true else { return }
        let breadcrumb = Breadcrumb(level: .info, category: "app")
        breadcrumb.message = event.name
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}
