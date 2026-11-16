import XCTest

/// Search and risk-filter flows in the review list.
final class SearchAndFilterFlowTests: SiftBarFlowTestCase {
    func testSearchFiltersCacheRows() {
        let app = AppLauncher.launchDemo(["--demo-page", "caches"])
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad(page: "Caches")
        dashboard.base.require(dashboard.row("Design Helper cache"), timeout: 15)

        let search = dashboard.searchField
        dashboard.base.require(search, timeout: 10)
        search.click()
        search.typeText("npm")

        dashboard.base.require(app.staticTexts["npm cache"], timeout: 10)
        XCTAssertTrue(
            app.staticTexts["Design Helper cache"].waitForNonExistence(timeout: 10),
            "search must hide rows that do not match"
        )

        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        dashboard.base.require(app.staticTexts["Design Helper cache"], timeout: 10)
    }

    func testLeftoverConfidenceIsVisibleFilterableAndLocksLowRows() {
        let app = AppLauncher.launchDemo(["--demo-page", "leftovers"])
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad(page: "Leftovers")
        dashboard.base.require(app.staticTexts["Possible leftover: OldApp"], timeout: 15)

        let high = dashboard.confidenceLabel(of: "Possible leftover: OldApp")
        dashboard.base.require(high, timeout: 10)
        dashboard.base.assertValueContains(high, "High")

        let low = dashboard.confidenceLabel(of: "Possible leftover: JetBrains")
        dashboard.base.require(low, timeout: 10)
        dashboard.base.assertValueContains(low, "Low")

        // Low confidence is review-only: there is no checkbox to select it.
        XCTAssertFalse(
            dashboard.selectCheckbox(for: "Possible leftover: JetBrains").exists,
            "low-confidence leftovers must not be selectable"
        )

        let picker = dashboard.confidencePicker
        dashboard.base.require(picker, timeout: 10)
        XCTAssertEqual(picker.value as? String, "All confidence")

        // All confidence -> High confidence (menu items are positional).
        picker.click()
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["Possible leftover: LegacyTool"].waitForNonExistence(timeout: 10),
            "the Medium row must disappear under the High filter"
        )
        dashboard.base.require(app.staticTexts["Possible leftover: OldApp"], timeout: 10)

        dashboard.base.require(dashboard.resetFilter, timeout: 5).click()
        dashboard.base.require(app.staticTexts["Possible leftover: LegacyTool"], timeout: 10)
    }

    func testRiskFilterNarrowsTheListAndResetRestoresIt() {
        let app = AppLauncher.launchDemo()
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad()
        dashboard.base.require(app.staticTexts["Xcode DerivedData"], timeout: 15)

        let picker = dashboard.riskPicker
        dashboard.base.require(picker, timeout: 10)
        XCTAssertEqual(picker.value as? String, "All risks")

        // SwiftUI picker menu items are exposed without labels on macOS, so
        // choose by position: All risks -> Safe -> Caution.
        picker.click()
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.staticTexts["Xcode DerivedData"].waitForNonExistence(timeout: 10),
            "the Safe-only row must disappear under the Caution filter"
        )
        XCTAssertTrue(app.staticTexts["Design Helper cache"].exists)

        let reset = dashboard.resetFilter
        dashboard.base.require(reset, timeout: 5)
        dashboard.base.assertLabel(reset, "Reset")
        reset.click()

        dashboard.base.require(app.staticTexts["Xcode DerivedData"], timeout: 10)
        XCTAssertEqual(picker.value as? String, "All risks")
    }
}
