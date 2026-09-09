import XCTest

@MainActor final class SampleUITests: XCTestCase {
    func testLocalActionsAndConsole() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let record = app.buttons["Record an action"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.tap()
        XCTAssertTrue(app.staticTexts["1"].exists || app.staticTexts["Recorded actions, 1"].exists)
        app.buttons["Try purchase"].tap()
        XCTAssertTrue(app.staticTexts["Purchase completed"].waitForExistence(timeout: 5))
        app.swipeUp()
        let console = app.buttons["Open console"]
        XCTAssertTrue(console.waitForExistence(timeout: 5))
        console.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Open console"].waitForExistence(timeout: 5))
    }
}
