import XCTest

/// Disk must open compact: summary and four plain groups first, technical
/// commands only after an explicit request.
final class DiskFlowTests: SiftBarFlowTestCase {
    func testDiskOpensCompactAndTechnicalDetailsAreOnDemand() {
        let app = AppLauncher.launchDemo(["--demo-page", "disk"])
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad(page: "Disk")

        dashboard.base.require(app.staticTexts["Where your space goes"], timeout: 15)
        // The rows combine their label and amount into one accessibility
        // element, so match the title as a prefix.
        dashboard.base.textContaining("Apps and tools", timeout: 10)
        dashboard.base.textContaining("Your files", timeout: 10)
        dashboard.base.textContaining("macOS and protected", timeout: 10)

        // The technical button lives inside the collapsed disclosure.
        XCTAssertFalse(app.buttons["disk.technical"].exists)
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'du -sk' OR value CONTAINS 'du -sk'")
            ).firstMatch.exists,
            "raw commands must stay out of the default Disk page"
        )

        let toggle = dashboard.diskDetailsToggle
        dashboard.base.require(toggle, timeout: 10).click()

        let technical = dashboard.base.linkOrButton("disk.technical")
        dashboard.base.require(technical, timeout: 10).click()

        dashboard.base.require(app.staticTexts["macOS volume layout"], timeout: 10)
        dashboard.base.require(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'du' OR value CONTAINS 'du'")
            ).firstMatch,
            timeout: 10
        )

        app.buttons["Done"].click()
    }
}
