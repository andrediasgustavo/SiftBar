import XCTest

/// Review flows: stats, selection, action bar, confirmation sheet.
/// Destructive actions are never confirmed here.
final class ReviewFlowTests: SiftBarFlowTestCase {
    func testOverviewShowsTheKeyNumbers() {
        let app = AppLauncher.launchDemo()
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad()
        dashboard.verifyOverviewStats()
    }

    func testCacheSelectionShowsActionBarAndConfirmation() {
        let app = AppLauncher.launchDemo(["--demo-page", "caches"])
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad(page: "Caches")
        dashboard.base.require(dashboard.row("Design Helper cache"), timeout: 15)

        dashboard.selectRow("Design Helper cache")
        dashboard.verifyStatus("selected")
        dashboard.verifyApplyLabel("Move to Trash…")
        dashboard.apply()

        let confirmation = ConfirmationPage(app: app)
        confirmation.waitToOpen(expectedConfirmLabel: "Move to Trash")
        confirmation.cancelAndWaitToClose()

        XCTAssertTrue(dashboard.row("Design Helper cache").exists)
    }

    func testProcessQuitRequiresConfirmation() {
        let app = AppLauncher.launchDemo()
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad()
        dashboard.openPage("Processes")
        dashboard.base.require(dashboard.row("Design Helper"), timeout: 15)

        dashboard.selectRow("Design Helper")
        dashboard.verifyApplyLabel("Quit Process…")
        dashboard.apply()

        let confirmation = ConfirmationPage(app: app)
        confirmation.waitToOpen(expectedConfirmLabel: "Quit")
        confirmation.cancelAndWaitToClose()

        XCTAssertTrue(dashboard.row("Design Helper").exists)
    }

    func testSelectAllAndDeselectUpdateTheActionBar() {
        let app = AppLauncher.launchDemo(["--demo-page", "caches"])
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad(page: "Caches")
        dashboard.selectAllChangeable()
        dashboard.verifyStatus("of 3 selected")

        dashboard.deselectAll()
        dashboard.verifyStatus("items can be changed")
    }

    /// Regression cover for c141ec3: the hover-only Finder button used to
    /// reserve width after the risk word, pushing it left of the impact value.
    func testRiskLabelAlignsWithTheImpactValue() {
        let app = AppLauncher.launchDemo(["--demo-page", "caches"])
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad(page: "Caches")

        let title = "Design Helper cache"
        let impact = app.staticTexts["row.impact.\(title)"]
        let risk = app.staticTexts["row.risk.\(title)"]

        dashboard.base.require(impact, timeout: 15)
        dashboard.base.require(risk, timeout: 5)
        dashboard.base.assertValueContains(impact, "GB")
        dashboard.base.assertValueContains(risk, "Caution")

        XCTAssertEqual(
            impact.frame.maxX,
            risk.frame.maxX,
            accuracy: 1,
            "the risk label must share the impact value's right edge"
        )
    }
}
