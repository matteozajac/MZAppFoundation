import Foundation
@preconcurrency import ReplayKit
import Testing
@testable import MZAppFoundationReporting

@MainActor @Suite(.timeLimit(.minutes(1))) struct RecordingSessionTests {
    @Test func shakeStopsRecordingWhenReplayKitCompletesOffMainActor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = CaptureDriverFixture()
        let session = RecordingSession(files: try ReportFiles(root: root), recorder: driver)
        session.update(enabled: true, active: true)
        await session.waitUntilSettled()
        #expect(session.isRecording)
        let frozen = try #require(session.freeze())
        await session.waitUntilSettled()
        #expect(!session.isRecording)
        #expect(driver.stopCount == 1)
        #expect(try await frozen.snapshot().isEmpty)
    }

    @Test func shakeDuringPermissionPromptStopsAfterStartCompletes() async throws {
        try await withSession { session, driver, _ in
            driver.holdStart = true
            session.update(enabled: true, active: true)
            await driver.waitForStarts(1)
            let frozen = try #require(session.freeze())
            #expect(session.freeze() == nil)
            #expect(driver.stopCount == 0)
            driver.releaseStart()
            await session.waitUntilSettled()
            #expect(driver.startCount == 1)
            #expect(driver.stopCount == 1)
            #expect(!session.isRecording)
            #expect(try await frozen.snapshot().isEmpty)
            #expect(driver.maximumConcurrentOperations == 1)
        }
    }

    @Test func closingConsoleDuringStopWaitsBeforeRestarting() async throws {
        try await withSession { session, driver, _ in
            session.update(enabled: true, active: true)
            await session.waitUntilSettled()
            driver.holdStop = true
            _ = session.freeze()
            await driver.waitForStops(1)
            session.resume()
            session.resume()
            #expect(driver.startCount == 1)
            driver.releaseStop()
            await session.waitUntilSettled()
            #expect(driver.startCount == 2)
            #expect(driver.stopCount == 1)
            #expect(session.isRecording)
            #expect(driver.maximumConcurrentOperations == 1)
        }
    }

    @Test func closingConsoleBeforePermissionCompletesStillStartsFreshHistory() async throws {
        try await withSession { session, driver, _ in
            driver.holdStart = true
            session.update(enabled: true, active: true)
            await driver.waitForStarts(1)
            _ = session.freeze()
            session.resume()
            driver.releaseStart()
            await session.waitUntilSettled()
            #expect(driver.startCount == 2)
            #expect(driver.stopCount == 1)
            #expect(session.isRecording)
            #expect(driver.maximumConcurrentOperations == 1)
        }
    }

    @Test func backgroundDuringPermissionPromptStopsAndCleansHistory() async throws {
        try await withSession { session, driver, root in
            driver.holdStart = true
            session.update(enabled: true, active: true)
            await driver.waitForStarts(1)
            session.update(enabled: true, active: false)
            driver.releaseStart()
            await session.waitUntilSettled()
            #expect(!session.isRecording)
            #expect(driver.stopCount == 1)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(remaining.isEmpty)
        }
    }

    @Test func deniedPermissionDoesNotLoopAndExplicitRetryStartsAgain() async throws {
        try await withSession { session, driver, root in
            driver.nextStartError = CocoaError(.userCancelled)
            session.update(enabled: true, active: true)
            await session.waitUntilSettled()
            #expect(!session.isRecording)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(remaining.isEmpty)
            session.update(enabled: true, active: false)
            session.update(enabled: true, active: true)
            await session.waitUntilSettled()
            #expect(driver.startCount == 1)
            session.retry()
            await session.waitUntilSettled()
            #expect(driver.startCount == 2)
            #expect(session.isRecording)
        }
    }

    @Test func rapidShakeCloseAndDeveloperToggleNeverOverlapCaptureOperations() async throws {
        try await withSession { session, driver, _ in
            session.update(enabled: true, active: true)
            await session.waitUntilSettled()
            for _ in 0..<25 {
                _ = session.freeze()
                session.update(enabled: false, active: true)
                session.resume()
                session.update(enabled: true, active: true)
                await session.waitUntilSettled()
                #expect(session.isRecording)
            }
            #expect(driver.startCount == 26)
            #expect(driver.stopCount == 25)
            #expect(driver.maximumConcurrentOperations == 1)
            session.update(enabled: false, active: true)
            await session.waitUntilSettled()
            #expect(!session.isRecording)
        }
    }

    @Test func captureErrorStopsOnceAndOldCaptureErrorCannotStopNewRecording() async throws {
        try await withSession { session, driver, _ in
            session.update(enabled: true, active: true)
            await session.waitUntilSettled()
            let sample = try BugReporterTests().sample(at: 0, landscape: false)
            let previousHandler = try #require(driver.handlers.first)
            previousHandler(sample, .video, CocoaError(.fileReadUnknown))
            await driver.waitForStops(1)
            await session.waitUntilSettled()
            #expect(!session.isRecording)
            session.retry()
            await session.waitUntilSettled()
            #expect(session.isRecording)
            previousHandler(sample, .video, CocoaError(.fileReadUnknown))
            for _ in 0..<20 { await Task.yield() }
            await session.waitUntilSettled()
            #expect(driver.startCount == 2)
            #expect(driver.stopCount == 1)
            #expect(session.isRecording)
        }
    }

    @Test(arguments: [false, true]) func unavailableOrBusyRecorderIsNotStarted(alreadyRecording: Bool) async throws {
        try await withSession { session, driver, _ in
            driver.isAvailable = alreadyRecording
            driver.isRecording = alreadyRecording
            session.update(enabled: true, active: true)
            await session.waitUntilSettled()
            #expect(driver.startCount == 0)
            #expect(driver.stopCount == 0)
            #expect(!session.isRecording)
        }
    }

    private func withSession(_ body: (RecordingSession, CaptureDriverFixture, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = CaptureDriverFixture()
        let session = RecordingSession(files: try ReportFiles(root: root), recorder: driver)
        var failure: (any Error)?
        do { try await body(session, driver, root) } catch { failure = error }
        driver.releaseStart()
        driver.releaseStop()
        session.update(enabled: false, active: false)
        await session.waitUntilSettled()
        if let failure { throw failure }
    }
}

@MainActor private final class CaptureDriverFixture: ScreenCaptureDriver {
    var isAvailable = true
    var isRecording = false
    var startCount = 0
    var stopCount = 0
    var maximumConcurrentOperations = 0
    var holdStart = false
    var holdStop = false
    var nextStartError: (any Error)?
    var handlers: [@Sendable (CMSampleBuffer, RPSampleBufferType, (any Error)?) -> Void] = []
    private var operations = 0
    private var startGate: CheckedContinuation<Void, Never>?
    private var stopGate: CheckedContinuation<Void, Never>?
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var stopWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func startCapture(handler: @escaping @Sendable (CMSampleBuffer, RPSampleBufferType, (any Error)?) -> Void) async throws {
        beginOperation()
        defer { operations -= 1 }
        startCount += 1
        handlers.append(handler)
        notifyWaiters()
        if holdStart { await withCheckedContinuation { startGate = $0 } }
        if let error = nextStartError {
            nextStartError = nil
            throw error
        }
        isRecording = true
    }

    func stopCapture() async {
        beginOperation()
        defer { operations -= 1 }
        stopCount += 1
        notifyWaiters()
        if holdStop { await withCheckedContinuation { stopGate = $0 } }
        isRecording = false
        await withCheckedContinuation { continuation in
            LegacyCompletionInvocation { @Sendable _ in continuation.resume() }.start()
        }
    }

    func releaseStart() {
        holdStart = false
        startGate?.resume()
        startGate = nil
    }

    func releaseStop() {
        holdStop = false
        stopGate?.resume()
        stopGate = nil
    }

    func waitForStarts(_ count: Int) async {
        guard startCount < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func waitForStops(_ count: Int) async {
        guard stopCount < count else { return }
        await withCheckedContinuation { stopWaiters.append((count, $0)) }
    }

    private func beginOperation() {
        operations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, operations)
    }

    private func notifyWaiters() {
        let readyStarts = startWaiters.filter { $0.0 <= startCount }
        startWaiters.removeAll { $0.0 <= startCount }
        let readyStops = stopWaiters.filter { $0.0 <= stopCount }
        stopWaiters.removeAll { $0.0 <= stopCount }
        for waiter in readyStarts + readyStops { waiter.1.resume() }
    }
}

/// An Objective-C selector deliberately models the SDK's unannotated callback
/// crossing a thread boundary. No Sendable conformance hides the production bug.
final class LegacyCompletionInvocation: NSObject {
    private let callback: ((any Error)?) -> Void
    init(_ callback: @escaping ((any Error)?) -> Void) { self.callback = callback }
    func start() {
        Thread.detachNewThreadSelector(#selector(invoke), toTarget: self, with: nil)
    }
    @objc func invoke() { callback(nil) }
}

@MainActor @Suite(.serialized) struct ReplayKitCompletionTests {
    @Test func nativeStopCompletionCanArriveOnBackgroundThread() async throws {
        let method = try #require(class_getInstanceMethod(RPScreenRecorder.self, #selector(RPScreenRecorder.stopCapture(handler:))))
        let replacement = replayKitStopImplementation()
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        // Invoke the real adapter and real Objective-C selector. A Swift-only
        // driver fixture does not reproduce the SDK's actor-checking thunk.
        await ReplayKitCaptureDriver().stopCapture()
    }
}

nonisolated private func replayKitStopImplementation() -> IMP {
    typealias Completion = @convention(block) (NSError?) -> Void
    let block: @convention(block) (AnyObject, Completion?) -> Void = { _, completion in
        LegacyCompletionInvocation { error in completion?(error as NSError?) }.start()
    }
    return imp_implementationWithBlock(block)
}
