import XCTest

/// The confirmation sheet that opens before any destructive action runs.
struct ConfirmationPage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var title: XCUIElement { app.staticTexts["Review 1 Action"] }
    var cancelButton: XCUIElement { app.buttons["sheet.cancel"] }
    var confirmButton: XCUIElement { app.buttons["sheet.confirm"] }

    func waitToOpen(expectedConfirmLabel: String? = nil) {
        base.require(title, timeout: 10)
        base.require(cancelButton, timeout: 5)
        base.assertLabel(cancelButton, "Cancel")

        base.require(confirmButton, timeout: 5)
        XCTAssertTrue(confirmButton.exists)
        if let expectedConfirmLabel {
            base.assertLabel(confirmButton, expectedConfirmLabel)
        }
    }

    /// Cancels and waits for the sheet to close. Nothing is executed.
    func cancelAndWaitToClose() {
        cancelButton.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
    }
}

/// The History sheet (⌘Y).
struct HistoryPage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var title: XCUIElement { app.staticTexts["History"] }
    var doneButton: XCUIElement { app.buttons["history.done"] }

    func openFromDashboard() {
        let history = app.buttons["header.history"]
        base.require(history, timeout: 10)
        history.click()
    }

    func waitToOpen() {
        base.require(title, timeout: 10)
        base.require(app.staticTexts["Actions applied by SiftBar."], timeout: 5)
        base.require(doneButton, timeout: 5)
        base.assertLabel(doneButton, "Done")
    }

    func close() {
        doneButton.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
    }
}

/// The result card shown after actions (synthetic in the demo build).
struct ResultCardPage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var headline: XCUIElement { app.staticTexts["result.headline"] }
    var showTrash: XCUIElement { app.links["result.show-trash"] }
    var dismiss: XCUIElement { base.linkOrButton("result.dismiss") }

    func waitToAppear() {
        base.require(headline, timeout: 20)
        base.assertValueContains(headline, "moved to Trash")

        base.require(base.textContaining("succeeded"), timeout: 5)
        base.require(showTrash, timeout: 5)
        base.assertLabel(showTrash, "Show Trash in Finder")

        base.require(dismiss, timeout: 5)
        base.assertLabel(dismiss, "Dismiss")
    }

    func dismissAndWaitToClose() {
        dismiss.click()
        XCTAssertTrue(headline.waitForNonExistence(timeout: 10))
    }
}
