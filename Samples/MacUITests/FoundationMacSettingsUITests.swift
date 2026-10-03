import XCTest

@MainActor final class FoundationMacSettingsUITests: XCTestCase {
    func testNativeSettingsSidebarConsoleShortcutsAndDeveloperRevocation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--foundation-settings-demo", "--ui-testing"]
        app.launch()
        app.activate()

        app.typeKey("d", modifierFlags: [.control, .command, .option])
        let settings = app.windows["mzappfoundation.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        let settingsWindow = settings
        XCTAssertTrue(settingsWindow.exists)
        let firebase = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Firebase,")).firstMatch
        XCTAssertTrue(firebase.waitForExistence(timeout: 5))
        firebase.click()
        XCTAssertTrue(valueRow(app, label: "Configuration file", value: "GoogleService-Info.plist missing").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(valueRow(app, label: "Runtime", value: "SDK not linked").exists)
        retainScreenshot(app, name: "macOS native settings and missing Firebase")

        app.typeKey("d", modifierFlags: [.command])
        let console = app.windows["Developer Console"]
        XCTAssertTrue(console.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(containingText(app, "The latest 500 local log messages.").exists)
        XCTAssertTrue(containingText(app, "developer_console_opened").waitForExistence(timeout: 10), app.debugDescription)
        retainScreenshot(app, name: "macOS native Pulse console")

        app.typeKey("d", modifierFlags: [.control, .command, .option])
        let disable = settingsWindow.descendants(matching: .any)["Disable developer options"].firstMatch
        for _ in 0..<8 {
            if disable.isHittable { break }
            settingsWindow.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        }
        XCTAssertTrue(disable.waitForExistence(timeout: 5))
        XCTAssertTrue(disable.isHittable, app.debugDescription)
        disable.click()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(console.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.windows["MZ Foundation"].descendants(matching: .any)["App Foundation"].exists)

        let developerMenu = app.menuBars.menuBarItems["Developer"]
        if developerMenu.exists { developerMenu.click() }
        XCTAssertFalse(app.menuItems["App Foundation"].exists)
        XCTAssertFalse(app.menuItems["Developer Console"].exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        let windowMenu = app.menuBars.menuBarItems["Window"]
        if windowMenu.exists {
            windowMenu.click()
            XCTAssertFalse(app.menuItems["App Foundation"].exists)
            XCTAssertFalse(app.menuItems["Developer Console"].exists)
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        }
        app.typeKey("d", modifierFlags: [.control, .command, .option])
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertFalse(settings.exists)
        XCTAssertFalse(console.exists)
        retainScreenshot(app, name: "macOS developer access revoked")
        app.terminate()
    }

    private func containingText(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func valueRow(_ app: XCUIApplication, label: String, value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label + ": " + value)).firstMatch
    }

    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
