import XCTest

@MainActor final class LoggingUITests: XCTestCase {
    func testStructuredErrorConsole() {
        let app = XCUIApplication()
        app.launchArguments = ["--logging-demo"]
        app.launch()
        let message = app.staticTexts["Sample model loading failed"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        message.tap()
        let info = app.buttons.matching(NSPredicate(format: "label == 'Info' OR label == 'More Info' OR label == 'info.circle'")).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 5), app.debugDescription)
        info.tap()
        let metadata = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", "error.cause")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Structured error details"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", "model_id")).firstMatch.exists)
    }
}
