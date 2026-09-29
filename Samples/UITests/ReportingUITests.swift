import XCTest

@MainActor final class ReportingUITests: XCTestCase {
    func testTitleReportAndValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.swipeUp()
        app.buttons["Open console"].tap()
        let ladybug = app.buttons["bugReporter.shareBug"]
        XCTAssertTrue(ladybug.waitForExistence(timeout: 10))
        ladybug.tap()
        let share = app.buttons["bugReporter.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertFalse(share.isEnabled)
        XCTAssertTrue(app.buttons["bugReporter.voiceRecord"].exists)
        let title = app.textFields["bugReporter.title"]
        title.tap()
        title.typeText("Cannot save changes")
        XCTAssertTrue(share.isEnabled)
        share.tap()
        dismissShareSheet(in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isEnabled)
        XCTAssertEqual(title.value as? String, "Cannot save changes")
        app.buttons["Cancel"].tap()
        app.buttons["Discard report"].tap()
        XCTAssertTrue(app.buttons["Open console"].waitForExistence(timeout: 5))
    }

    /// Requires a functioning simulator/device microphone; never substitute synthetic audio.
    func testLiveMicrophoneReportAndTitleFallback() throws {
        guard ProcessInfo.processInfo.environment["MZ_TEST_LIVE_MICROPHONE"] == "1" else {
            throw XCTSkip("Opt in with MZ_TEST_LIVE_MICROPHONE=1 on a host with working audio input.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.swipeUp()
        let console = app.buttons["Open console"]
        XCTAssertTrue(console.waitForExistence(timeout: 10))
        console.tap()
        let ladybug = app.buttons["bugReporter.shareBug"]
        XCTAssertTrue(ladybug.waitForExistence(timeout: 10))
        ladybug.tap()
        let share = app.buttons["bugReporter.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertFalse(share.isEnabled)
        app.buttons["bugReporter.voiceRecord"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if permission.waitForExistence(timeout: 3) { permission.tap() }
        let okay = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["OK"]
        if okay.exists { okay.tap() }
        let stop = app.buttons["bugReporter.voiceStop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        // Wait for enough real recorded frames to survive the minimum-duration check.
        sleep(2)
        stop.tap()
        let play = app.buttons["bugReporter.voicePlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(share.isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Voice report without a title"
        capture.lifetime = .keepAlways
        add(capture)
        play.tap()
        XCTAssertTrue(app.buttons["bugReporter.voiceStopPlayback"].waitForExistence(timeout: 3))
        app.buttons["bugReporter.voiceStopPlayback"].tap()
        share.tap()
        dismissShareSheet(in: app)
        let delete = app.buttons["bugReporter.voiceDelete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(share.isEnabled)
        let title = app.textFields["bugReporter.title"]
        XCTAssertTrue(title.exists, app.debugDescription)
        title.tap()
        title.typeText("Cannot save changes")
        XCTAssertTrue(share.isEnabled)
        app.buttons["Cancel"].tap()
        app.buttons["Discard report"].tap()
        XCTAssertTrue(console.waitForExistence(timeout: 5))
    }

    private func dismissShareSheet(in app: XCUIApplication) {
        let popoverDismiss = app.otherElements["PopoverDismissRegion"]
        if popoverDismiss.waitForExistence(timeout: 3) {
            popoverDismiss.tap()
        } else {
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
            close.tap()
        }
    }

}
