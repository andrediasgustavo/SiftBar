import XCTest

/// The optional Full Disk Access flow, presented as a sheet over demo data.
struct AccessOnboardingPage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var introductionTitle: XCUIElement { app.staticTexts["Include Personal Folders"] }
    var waitingTitle: XCUIElement { app.staticTexts["Finish Full Disk Access"] }
    var openSettings: XCUIElement { app.buttons["access.open-settings"] }
    var restart: XCUIElement { app.buttons["access.restart"] }
    var folderPrompts: XCUIElement { base.linkOrButton("access.folder-prompts") }
    var notNow: XCUIElement { app.buttons["access.not-now"] }
    var status: XCUIElement { app.descendants(matching: .any)["access.status"] }

    func waitForIntroduction() {
        _ = base.require(introductionTitle, timeout: 20)
        _ = base.require(openSettings, timeout: 5)
        base.assertLabel(openSettings, "Open Full Disk Settings…")
        _ = base.require(notNow, timeout: 5)
        _ = base.require(folderPrompts, timeout: 5)
        let statusElement = base.require(status, timeout: 5)
        let statusLabel = statusElement.label
        let statusValue = statusElement.value as? String ?? ""
        XCTAssertTrue(
            statusLabel.contains("Personal folders not included")
                || statusValue.contains("Personal folders not included"),
            "unexpected access status: label=\(statusLabel), value=\(statusValue)"
        )

        XCTAssertFalse(restart.exists, "Restart belongs only to the completion step")
        XCTAssertFalse(app.buttons["Check again"].exists, "Access is checked automatically after restart")
    }

    func openFullDiskSettings() {
        openSettings.click()
    }

    func waitForCompletionStep() {
        _ = base.require(waitingTitle, timeout: 10)
        _ = base.require(restart, timeout: 5)
        base.assertLabel(restart, "Restart & Check Access")
        XCTAssertFalse(openSettings.exists)
        XCTAssertFalse(app.buttons["Check again"].exists)
    }

    func restartAndCheckAccess() {
        restart.click()
    }
}
