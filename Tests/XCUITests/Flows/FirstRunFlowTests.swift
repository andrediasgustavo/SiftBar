import XCTest

/// First-run and first-scan flows.
final class FirstRunFlowTests: SiftBarFlowTestCase {
    func testFirstRunShowsASinglePrimaryAction() {
        let app = AppLauncher.launchFirstRun()
        let firstRun = FirstRunPage(app: app)

        firstRun.waitToLoad()
        firstRun.verifySinglePrimaryAction()
    }

    func testAnalyzeAndStopReturnsToWelcome() {
        let app = AppLauncher.launchFirstRun()
        let firstRun = FirstRunPage(app: app)

        firstRun.waitToLoad()
        firstRun.runAnalysis()

        let workspace = ScanWorkspacePage(app: app)
        workspace.waitToAppear()
        workspace.stop()

        firstRun.waitToLoad()
    }
}
