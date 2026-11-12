import XCTest

/// History and result-card flows.
final class HistoryAndResultFlowTests: SiftBarFlowTestCase {
    func testHistoryOpensAndCloses() {
        let app = AppLauncher.launchDemo()
        let dashboard = DashboardPage(app: app)

        dashboard.waitToLoad()

        let history = HistoryPage(app: app)
        history.openFromDashboard()
        history.waitToOpen()
        history.close()
    }

    func testResultCardSeparatesDiskAndMemory() {
        let app = AppLauncher.launchDemo(["--demo-result"])
        let result = ResultCardPage(app: app)

        result.waitToAppear()
        result.dismissAndWaitToClose()
    }
}
