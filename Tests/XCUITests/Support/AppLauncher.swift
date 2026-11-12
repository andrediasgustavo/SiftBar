import XCTest

/// Shared setup for every flow test.
class SiftBarFlowTestCase: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }
}

/// Central launch configuration for the interaction suite.
///
/// Tests never confirm a destructive action, so they only need the demo
/// report (deterministic, synthetic) or the first-run screen (no report).
/// The launch argument suppresses the one-time Full Disk Access sheet so the
/// hero is directly queryable (NSUserDefaults argument domain).
enum AppLauncher {
    static func launchDemo(_ extra: [String] = []) -> XCUIApplication {
        launch(["--demo"] + extra)
    }

    static func launchFirstRun() -> XCUIApplication {
        launch(["--show-dashboard", "-SiftBar.hasSeenAccessOnboarding", "YES"])
    }

    private static func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        // The dashboard is an accessory (menu bar) app: bring it forward so
        // clicks and menus are hittable while Xcode/xcodebuild is active.
        app.activate()
        _ = app.windows.firstMatch.waitForExistence(timeout: 20)
        return app
    }
}
