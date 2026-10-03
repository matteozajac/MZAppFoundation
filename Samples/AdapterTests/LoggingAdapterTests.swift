import XCTest
import MZAppFoundation
import Pulse
import Sentry
@testable import MZAppFoundationLive
import MZAppFoundationLocal

@MainActor final class LoggingAdapterTests: XCTestCase {
    func testPulsePersistsReadableErrorMetadataAndCaller() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pulse")
        let store = try LoggerStore(storeURL: url, options: [.create, .synchronous])
        let logger = PulseLogger(store: store)
        logger.error("Model loading failed", error: ReadableError(), category: "model",
                     metadata: ["model_id": .string("sample")], file: "App/Loader.swift", function: "load()", line: 42)
        let messages = try store.messages()
        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.text, "Model loading failed")
        XCTAssertEqual(message.metadata["error.cause.0.message"], "Model weights are unavailable")
        XCTAssertEqual(message.metadata["error.stack"], "supplied")
        XCTAssertEqual(message.metadata["error.stack.00"], "Loader.load() + 42")
        XCTAssertEqual(message.metadata["model_id"], "sample")
        XCTAssertNil(message.metadata["mz_record_id"])
        XCTAssertEqual(message.file, "Loader.swift")
        XCTAssertEqual(message.function, "load()")
        XCTAssertEqual(message.line, 42)
    }

    func testSentryPayloadContainsExceptionAndSeparateContext() throws {
        let error = NSError(domain: "ModelLoader", code: -42, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: -1009),
            NSLocalizedDescriptionKey: "private transcript and credentials"
        ])
        let snapshot = ErrorSnapshot(error, file: "App/Loader.swift", function: "load()", line: 42)
        let issue = DiagnosticIssue(code: "Model loading failed", category: "model",
                                    metadata: ["model_id": .string("sample"), "user_id": .string("private-user"),
                                               "access_token": .string("private-token")], error: snapshot, source: snapshot.source)
        // Inspect the exact serializable event passed to capture, without starting a remote transport.
        let event = SentryDiagnostics.event(for: issue)
        XCTAssertEqual(event.message?.formatted, "Model loading failed")
        XCTAssertEqual(event.exceptions?.count, 2)
        XCTAssertEqual(event.exceptions?.last?.module, "ModelLoader")
        XCTAssertEqual(event.exceptions?.last?.value, "ModelLoader (-42)")
        XCTAssertFalse(try XCTUnwrap(event.exceptions?.last?.stacktrace?.frames).isEmpty)
        XCTAssertEqual(event.context?["app_diagnostic"]?["stack_origin"] as? String, "reporting")
        XCTAssertEqual(event.context?["app_diagnostic"]?["file"] as? String, "App/Loader.swift")
        let serialized = String(describing: event.serialize())
        XCTAssertFalse(serialized.contains("private transcript"))
        XCTAssertFalse(serialized.contains("private-user"))
        XCTAssertFalse(serialized.contains("private-token"))
        XCTAssertTrue(serialized.contains("model_id"))
    }
}

private struct ReadableError: LoggableError, ErrorStackProviding {
    var logMessage: String { "Model weights are unavailable" }
    var logStack: ErrorStack { .init(origin: .supplied, symbols: ["Loader.load() + 42"]) }
}
