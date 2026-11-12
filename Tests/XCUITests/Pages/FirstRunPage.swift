import XCTest

/// The first-run screen shown while no report exists.
struct FirstRunPage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var welcomeTitle: XCUIElement { app.staticTexts["Welcome to SiftBar"] }
    var analyzeButton: XCUIElement { app.buttons["first-run.analyze"] }
    var grantAccess: XCUIElement { app.links["first-run.grant-access"] }
    var headerHistory: XCUIElement { app.buttons["header.history"] }
    var headerAnalyze: XCUIElement { app.buttons["header.analyze"] }

    func waitToLoad() {
        base.require(welcomeTitle, timeout: 20)
    }

    /// The first-run invariant: exactly one primary action on the window.
    func verifySinglePrimaryAction() {
        base.require(analyzeButton, timeout: 5)
        base.assertLabel(analyzeButton, "Run First Analysis")

        base.require(headerHistory, timeout: 5)
        base.assertLabel(headerHistory, "History")

        XCTAssertFalse(
            headerAnalyze.exists,
            "the header must not duplicate the first-run Analyze button"
        )
    }

    func runAnalysis() {
        analyzeButton.click()
    }
}

/// The full-screen workspace shown while the first scan runs.
struct ScanWorkspacePage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var title: XCUIElement { app.staticTexts["Analyzing your Mac"] }
    var stopButton: XCUIElement { app.buttons["scan.stop"] }

    func waitToAppear() {
        base.require(title, timeout: 30)
        base.require(stopButton, timeout: 10)
        base.assertLabel(stopButton, "Stop")
    }

    func stop() {
        stopButton.click()
    }
}
