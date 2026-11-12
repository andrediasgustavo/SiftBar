import XCTest

/// Interaction tests that need a real window server and the XCUITest runner.
/// They run on CI (full Xcode) through `xcodegen generate` + `xcodebuild test`;
/// `scripts/check.sh` runs them locally only when both tools are installed.
final class SiftBarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testFirstRunShowsASinglePrimaryAction() {
        // The argument suppresses the one-time Full Disk Access sheet so the
        // hero is directly queryable (NSUserDefaults argument domain).
        let app = launch([
            "--show-dashboard",
            "-SiftBar.hasSeenAccessOnboarding", "YES"
        ])

        XCTAssertTrue(
            app.staticTexts["Welcome to SiftBar"].waitForExistence(timeout: 20)
        )
        XCTAssertTrue(app.buttons["first-run.analyze"].exists)
        XCTAssertTrue(app.buttons["header.history"].exists)
        XCTAssertFalse(
            app.buttons["header.analyze"].exists,
            "The header must not duplicate the first-run Analyze button"
        )
    }

    func testDemoDashboardSelectsAnItemAndOpensTheConfirmation() {
        let app = launch(["--demo"])

        XCTAssertTrue(app.staticTexts["Overview"].firstMatch.waitForExistence(timeout: 20))

        let caches = app.staticTexts["Caches"].firstMatch
        XCTAssertTrue(caches.waitForExistence(timeout: 10))
        caches.click()

        XCTAssertTrue(app.staticTexts["Design Helper cache"].waitForExistence(timeout: 10))

        let checkbox = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Select '")
        ).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.click()

        let apply = app.buttons["action-bar.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertTrue(apply.isEnabled)
        apply.click()

        XCTAssertTrue(app.staticTexts["Review 1 Action"].waitForExistence(timeout: 10))

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
    }
}
