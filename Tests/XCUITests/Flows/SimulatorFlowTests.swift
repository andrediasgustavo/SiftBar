import XCTest

/// Simulator deletion must always pass through the confirmation sheet with the
/// exact simctl command, and cancellation must never delete anything.
final class SimulatorFlowTests: SiftBarFlowTestCase {
    func testSimulatorDeletionRequiresConfirmationWithSIMCTLPreview() {
        let app = AppLauncher.launchDemo(["--demo-simulators", "--demo-page", "caches"])
        let dashboard = DashboardPage(app: app)
        let confirmation = ConfirmationPage(app: app)

        dashboard.waitToLoad(page: "Caches")
        dashboard.base.require(app.staticTexts["iPhone 16 Pro simulator"], timeout: 15)

        dashboard.selectRow("iPhone 16 Pro simulator")
        dashboard.verifyApplyLabel("Delete Simulator…")
        dashboard.apply()

        confirmation.waitToOpen(expectedConfirmLabel: "Delete")
        dashboard.base.textContaining("xcrun simctl delete AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        dashboard.base.textContaining("cannot be undone")
        confirmation.cancelAndWaitToClose()
        XCTAssertTrue(app.staticTexts["iPhone 16 Pro simulator"].exists)

        // Same launch: the safe bulk path for devices whose runtime is gone.
        dashboard.deselectAll()
        dashboard.selectRow("Unavailable simulators")
        dashboard.verifyApplyLabel("Delete Unavailable Simulators…")
        dashboard.apply()

        confirmation.waitToOpen(expectedConfirmLabel: "Delete")
        dashboard.base.textContaining("xcrun simctl delete unavailable")
        confirmation.cancelAndWaitToClose()
        XCTAssertTrue(app.staticTexts["Unavailable simulators"].exists)
    }
}
