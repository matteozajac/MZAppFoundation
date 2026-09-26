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
        let event = Self.event(for: issue)
        SentrySDK.capture(event: event)
        return .recorded
    }
    /// Pure mapping also used by adapter tests; no SDK initialization or transport.
    static func event(for issue: DiagnosticIssue) -> Event {
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: issue.code)
        event.tags = ["issue_code": issue.code, "issue_category": issue.category]
        var context: [String: Any] = issue.metadata.mapValues { $0.rendered }
        context["file"] = issue.source.file
        context["function"] = issue.source.function
        context["line"] = issue.source.line
        if let error = issue.error {
            context["stack_origin"] = error.stack.origin.rawValue
            context["stack_symbols"] = error.stack.symbols
            event.exceptions = error.causes.reversed().map { cause in
                let exception = Exception(value: cause.message ?? "\(cause.domain) (\(cause.code))", type: cause.type)
                exception.module = cause.domain
                return exception
            }
            let frames = error.stack.symbols.enumerated().reversed().map { index, symbol in
                let frame = Frame()
                frame.function = symbol
                if error.stack.addresses.indices.contains(index) {
                    frame.instructionAddress = "0x" + String(error.stack.addresses[index], radix: 16)
                }
                return frame
            }
            event.exceptions?.last?.stacktrace = SentryStacktrace(frames: frames, registers: [:])
        }
        event.context = ["app_diagnostic": context]
        return event
    }

    func breadcrumb(_ event: TelemetryEvent) {
        guard gate?.allowsDelivery == true else { return }
        let breadcrumb = Breadcrumb(level: .info, category: "app")
        breadcrumb.message = event.name
        SentrySDK.addBreadcrumb(breadcrumb)
    }
}
