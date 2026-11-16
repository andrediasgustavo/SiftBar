import XCTest

/// The dashboard with a loaded report (demo data in the tests).
struct DashboardPage {
    let app: XCUIApplication
    var base: BasePage { BasePage(app: app) }

    var headerAnalyze: XCUIElement { app.buttons["header.analyze"] }
    var headerHistory: XCUIElement { app.buttons["header.history"] }
    var headerExport: XCUIElement { app.buttons["header.export"] }
    var searchField: XCUIElement { app.searchFields["filter.search"] }
    var riskPicker: XCUIElement {
        base.control([app.popUpButtons], identifier: "filter.risk", label: "Risk")
    }
    var selectMenu: XCUIElement {
        base.control([app.menuButtons, app.popUpButtons], identifier: "filter.select", label: "Select")
    }
    var confidencePicker: XCUIElement {
        base.control(
            [app.popUpButtons, app.menuButtons],
            identifier: "filter.confidence",
            label: "Confidence"
        )
    }

    /// SwiftUI exposes a DisclosureGroup as a button on some SDKs and as a
    /// clickable static text on others.
    var diskDetailsToggle: XCUIElement {
        let triangle = app.disclosureTriangles["disk.details"]
        if triangle.exists { return triangle }

        let button = app.buttons["disk.details"]
        if button.exists { return button }

        let labelled = app.buttons["Show details"]
        if labelled.exists { return labelled }

        return app.staticTexts["Show details"]
    }
    var resetFilter: XCUIElement { base.linkOrButton("filter.reset") }
    var applyButton: XCUIElement { app.buttons["action-bar.apply"] }
    var deselect: XCUIElement { base.linkOrButton("action-bar.deselect") }
    var actionBarStatus: XCUIElement { app.staticTexts["action-bar.status"] }

    func waitToLoad(page: String = "Overview") {
        base.require(app.staticTexts[page].firstMatch, timeout: 20)
        base.require(headerAnalyze, timeout: 10)
        base.assertLabel(headerAnalyze, "Analyze")
        base.assertLabel(headerHistory, "History")
        base.require(headerExport, timeout: 5)
        XCTAssertFalse(app.buttons["first-run.analyze"].exists)
    }

    func openPage(_ name: String) {
        let row = app.staticTexts[name].firstMatch
        base.require(row, timeout: 15)
        row.click()
    }

    /// The key numbers every report must show.
    func verifyOverviewStats() {
        base.require(base.textContaining("Found 24 items"), timeout: 10)
        base.require(base.textContaining("Findings"), timeout: 5)
        base.require(base.textContaining("Need review"), timeout: 5)
        base.require(base.textContaining("Disk available"), timeout: 5)
    }

    func row(_ title: String) -> XCUIElement {
        app.staticTexts[title]
    }

    func selectRow(_ title: String) {
        let checkbox = app.buttons["row.select.\(title)"]
        base.require(checkbox, timeout: 10)
        checkbox.click()
    }

    func riskLabel(of title: String) -> XCUIElement {
        app.staticTexts["row.risk.\(title)"]
    }

    func confidenceLabel(of title: String) -> XCUIElement {
        app.staticTexts["row.confidence.\(title)"]
    }

    func selectCheckbox(for title: String) -> XCUIElement {
        app.buttons["row.select.\(title)"]
    }

    /// Selects every changeable row through the bulk menu.
    func selectAllChangeable() {
        base.require(selectMenu, timeout: 10)
        selectMenu.click()

        let all = app.menuItems["All Changeable"]
        base.require(all, timeout: 5)
        all.click()
    }

    func verifyApplyLabel(_ expected: String) {
        base.require(applyButton, timeout: 10)
        base.assertLabel(applyButton, expected)
    }

    func apply() {
        applyButton.click()
    }

    func verifyStatus(_ needle: String) {
        base.require(actionBarStatus, timeout: 10)
        base.assertValueContains(actionBarStatus, needle)
    }

    func deselectAll() {
        base.require(deselect, timeout: 5)
        deselect.click()
    }
}
