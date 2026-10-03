import XCTest

@MainActor final class FoundationSettingsUITests: XCTestCase {
    func testKeyboardShortcutHelpStaysAvailableWithoutDeveloperMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let mode = app.switches["Developer mode"]
        for _ in 0..<5 { if mode.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        if mode.value as? String == "1" { mode.switches.firstMatch.tap() }
        let help = app.buttons["mz.foundation.shortcuts.link"]
        help.tap()
        XCTAssertTrue(app.staticTexts["Developer Console"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mz.foundation.shortcuts.developerDisabled"].exists || app.otherElements["mz.foundation.shortcuts.developerDisabled"].exists)
        retainScreenshot(app, name: "Keyboard shortcuts with developer mode off")
        app.buttons["Done"].tap()
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mz.foundation.settings.link"].exists)
    }
    func testExpandedDiagnosticsAndIssueFilter() {
        let app = XCUIApplication()
        openSettings(app, arguments: ["--foundation-expanded-demo"])
        let toggle = app.switches["mz.foundation.issuesOnly"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["mz.foundation.provider.firebase"].exists)
        XCTAssertFalse(app.buttons["mz.foundation.provider.revenueCat"].exists)
        app.buttons["mz.foundation.provider.firebase"].tap()
        XCTAssertTrue(app.staticTexts["required"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This app requires Firebase, but its configuration is unavailable or invalid."].exists)
        retainScreenshot(app, name: "Required provider findings")
        app.navigationBars.buttons["Foundation"].tap()
        toggle.switches.firstMatch.tap()
        tapRow(app, title: "Sample service")
        XCTAssertTrue(app.staticTexts["SDK-free sample composition"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Foundation"].tap()
        tapRow(app, title: "Telemetry counters")
        XCTAssertTrue(app.staticTexts["Schema rejected"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Foundation"].tap()
        tapRow(app, title: "Export diagnostics")
        app.buttons["mz.foundation.export.capture"].tap()
        XCTAssertTrue(app.buttons["Save JSON"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy text"].exists)
        retainScreenshot(app, name: "Diagnostics export preview")
    }

    func testDeveloperLinkDryRunAndLocalPendingScenario() {
        let app = XCUIApplication()
        openSettings(app)
        tapRow(app, title: "Links and QR codes")
        let field = app.descendants(matching: .any)["mz.foundation.link.input"].firstMatch
        for _ in 0..<5 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("mzappfoundation://sample/developer/enable?secret=hidden")
        app.buttons["mz.foundation.link.inspect"].tap()
        XCTAssertTrue(app.staticTexts["Rejected"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Foundation"].tap()
        tapRow(app, title: "Local QA scenarios")
        XCTAssertTrue(app.staticTexts["Simulated services"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Scenario")).firstMatch.tap()
        app.buttons["Pending purchase"].tap()
        tapRow(app, title: "Try mock purchase")
        let pending = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Mock purchase pending")).firstMatch
        for _ in 0..<3 { if pending.exists { break }; app.swipeUp() }
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "None")).firstMatch.exists)
        retainScreenshot(app, name: "Isolated pending QA purchase")
    }

    func testConsolidatedBugReportingIncludesDiagnostics() {
        let app = XCUIApplication()
        openSettings(app)
        tapRow(app, title: "Bug reporting and recording")
        let open = app.buttons["mz.foundation.report.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let shareBug = app.buttons["bugReporter.shareBug"]
        XCTAssertTrue(shareBug.waitForExistence(timeout: 5))
        shareBug.tap()
        let diagnostics = app.switches["bugReporter.diagnostics"]
        for _ in 0..<6 { if diagnostics.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertEqual(diagnostics.value as? String, "1")
        retainScreenshot(app, name: "Bug report diagnostics attachment")
    }

    func testPulseConsoleUsesSharedBugReporter() {
        let app = XCUIApplication()
        openSettings(app)
        tapRow(app, title: "Pulse console")
        let open = app.buttons["mz.foundation.report.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let ladybug = app.buttons["bugReporter.shareBug"]
        XCTAssertTrue(ladybug.waitForExistence(timeout: 5))
        retainScreenshot(app, name: "Pulse console with Ladybug reporting")
        ladybug.tap()
        let share = app.buttons["bugReporter.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        let title = app.textFields["bugReporter.title"]
        title.tap()
        title.typeText("Report from Foundation console")
        XCTAssertTrue(share.isEnabled)
        app.buttons["Cancel"].tap()
        app.buttons["Discard report"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(ladybug.waitForExistence(timeout: 5))
    }

    private func openSettings(_ app: XCUIApplication, arguments: [String] = []) {
        app.launchArguments = ["--ui-testing", "--foundation-settings-demo"] + arguments
        app.launch()
        let link = app.buttons["mz.foundation.settings.link"]
        for _ in 0..<5 { if link.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.staticTexts["0.5.1"].waitForExistence(timeout: 5))
    }

    private func tapRow(_ app: XCUIApplication, title: String) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        for _ in 0..<6 { if row.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), title)
        row.tap()
    }

    func testOptionalProviderDetailsAndDeveloperDisable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--foundation-settings-demo"]
        app.launch()
        app.swipeUp()
        let link = app.buttons["mz.foundation.settings.link"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.staticTexts["0.5.1"].waitForExistence(timeout: 5))
        retainScreenshot(app, name: "Foundation overview")
        let firebase = app.buttons["mz.foundation.provider.firebase"]
        if !firebase.isHittable { app.swipeUp() }
        firebase.tap()
        XCTAssertTrue(app.staticTexts["Missing configuration"].waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if app.staticTexts["GoogleService-Info.plist missing"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["GoogleService-Info.plist missing"].exists)
        retainScreenshot(app, name: "Missing Firebase configuration")
        app.navigationBars.buttons["Foundation"].tap()
        app.buttons["mz.foundation.provider.revenueCat"].tap()
        XCTAssertTrue(app.staticTexts["Not configured"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Foundation"].tap()
        app.buttons["mz.foundation.provider.sentry"].tap()
        XCTAssertTrue(app.staticTexts["Not configured"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Foundation"].tap()
        let disable = app.buttons["mz.foundation.disable"]
        for _ in 0..<5 {
            if disable.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(disable.waitForExistence(timeout: 5))
        disable.tap()
        XCTAssertFalse(link.waitForExistence(timeout: 2))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.swipeUp()
        XCTAssertFalse(app.buttons["mz.foundation.settings.link"].exists)
        let mode = app.switches["Developer mode"]
        mode.switches.firstMatch.tap()
        XCTAssertEqual(mode.value as? String, "1")
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["0.5.1"].exists)
        link.tap()
        XCTAssertTrue(app.staticTexts["0.5.1"].waitForExistence(timeout: 5))
    }

    private func retainScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
