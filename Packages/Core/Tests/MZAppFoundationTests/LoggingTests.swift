import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct LoggingTests {
    @Test func errorEvidenceSurvivesRedactionAndRouting() throws {
        let sink = RecordingLogger()
        let local = TestLogEngine(logger: sink)
        let remote = RecordingDiagnosticsEngine(delivery: .remote)
        let telemetry = Telemetry(configuration: .init(bundleIdentifier: "test", urlScheme: "test", environment: .local),
                                  schema: .init(events: [:]), diagnostics: [local, remote])
        let logger = DiagnosticsLogger(local: sink, diagnostics: telemetry)
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009,
                                 userInfo: [NSLocalizedDescriptionKey: "secret transcript /Users/person/audio.wav"])
        let error = NSError(domain: "ModelLoader", code: -42,
                            userInfo: [NSUnderlyingErrorKey: underlying, "token": "private"])
        logger.error("Model loading failed", error: error, category: "model",
                     metadata: ["model_id": .string("small"), "token": .string("private")],
                     file: "Feature/Loader.swift", function: "load()", line: 42)
        let entry = try #require(sink.entries.first)
        #expect(sink.entries.count == 1)
        #expect(remote.issues.isEmpty)
        #expect(entry.message == "Model loading failed")
        #expect(entry.metadata == ["model_id": .string("small")])
        #expect(entry.source == LogSource(file: "Feature/Loader.swift", function: "load()", line: 42))
        let snapshot = try #require(entry.error)
        #expect(snapshot.causes.map(\.code) == [-42, -1009])
        #expect(snapshot.causes.map(\.domain) == ["ModelLoader", NSURLErrorDomain])
        #expect(snapshot.causes.allSatisfy { $0.message == nil })
        #expect(snapshot.stack.origin == .reporting)
        #expect(!snapshot.stack.symbols.isEmpty)
        #expect(snapshot.stack.symbols.count <= 64)
    }

    @Test func messageOnlyAndCancellation() {
        let logger = RecordingLogger()
        logger.error("Unexpected state")
        logger.error("Cancelled", error: CancellationError())
        logger.error("Cancelled URL", error: URLError(.cancelled))
        #expect(logger.entries.count == 1)
        #expect(logger.entries[0].error == nil)
        #expect(logger.entries[0].source.file == "MZAppFoundationTests/LoggingTests.swift")
        #expect(logger.entries[0].source.function == "messageOnlyAndCancellation()")
    }

    @Test func suppliedStackAndAuditedTechnicalText() throws {
        let snapshot = ErrorSnapshot(SampleError())
        #expect(snapshot.stack.origin == .supplied)
        #expect(snapshot.stack.symbols == ["original failure site"])
        let message = try #require(snapshot.causes.first?.message)
        #expect(message.contains("Decoder failed"))
        #expect(!message.contains("private@example.com"))
        #expect(!message.contains("secret-token"))
        #expect(!message.contains("/Users/person"))
    }

    @Test func cyclicUnderlyingErrorsAreBounded() {
        let snapshot = ErrorSnapshot(CyclicError())
        #expect(snapshot.causes.count <= 8)
        #expect(snapshot.causes.allSatisfy { $0.code == -7 })
    }

    @Test func localFallbackNeverReentersDiagnostics() {
        let local = RecordingLogger()
        let diagnostics = RecordingDiagnosticReporter()
        let logger = DiagnosticsLogger(local: local, diagnostics: diagnostics)
        logger.log(LogEntry("Delivery failed", level: .error, error: ErrorSnapshot(NSError(domain: "delivery", code: -1)),
                            reportsToDiagnostics: false))
        #expect(local.entries.count == 1)
        #expect(diagnostics.count == 0)
    }

    @Test func underlyingDepthIsBounded() {
        var error = NSError(domain: "root", code: 0)
        for index in 1...20 {
            error = NSError(domain: "wrapper", code: index, userInfo: [NSUnderlyingErrorKey: error])
        }
        let snapshot = ErrorSnapshot(error)
        #expect(snapshot.causes.count == 8)
        #expect(snapshot.causes.first?.code == 20)
        #expect(snapshot.causes.last?.code == 13)
    }
}

private struct SampleError: LoggableError, ErrorStackProviding {
    var logMessage: String { "Decoder failed private@example.com token=secret-token /Users/person/audio.wav" }
    var logStack: ErrorStack { .init(origin: .supplied, symbols: ["original failure site"]) }
}

@MainActor private final class TestLogEngine: DiagnosticsEngine {
    let delivery = DeliveryKind.local
    let logger: RecordingLogger
    init(logger: RecordingLogger) { self.logger = logger }
    func setEnabled(_ enabled: Bool) {}
    func breadcrumb(_ event: TelemetryEvent) {}
    func record(_ issue: DiagnosticIssue) -> EngineResult {
        logger.log(LogEntry(issue.code, level: .error, category: issue.category, metadata: issue.metadata,
                            error: issue.error, source: issue.source))
        return .recorded
    }
}

private struct CyclicError: CustomNSError {
    static var errorDomain: String { "cycle" }
    var errorCode: Int { -7 }
    var errorUserInfo: [String: Any] { [NSUnderlyingErrorKey: self] }
}

@MainActor private final class RecordingDiagnosticReporter: DiagnosticsReporting {
    var count = 0
    func record(_ issue: DiagnosticIssue) { count += 1 }
    func breadcrumb(_ event: any AnalyticsEvent) {}
}
