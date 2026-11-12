import AppKit
import Darwin
import XCTest

/// Regression coverage for the access sheet and the real application restart.
final class AccessFlowTests: SiftBarFlowTestCase {
    func testRestartCreatesANewProcessAndChecksAccess() {
        let app = AppLauncher.launchAccessOnboarding()
        let onboarding = AccessOnboardingPage(app: app)

        onboarding.waitForIntroduction()
        onboarding.openFullDiskSettings()
        onboarding.waitForCompletionStep()

        guard let originalProcess = newestSiftBarProcess() else {
            XCTFail("The launched test process was not found")
            return
        }

        onboarding.restartAndCheckAccess()

        // XCUIApplication has no processIdentifier property on macOS. Track
        // NSRunningApplication instead, including the previous process's
        // termination, so window reactivation cannot pass as a restart.
        var newProcess: NSRunningApplication?
        let relaunched = XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak self] _, _ in
                guard let candidate = self?.newestSiftBarProcess(),
                      candidate.processIdentifier != originalProcess.processIdentifier else {
                    return false
                }
                newProcess = candidate
                return true
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [relaunched], timeout: 20), .completed)

        guard let newProcess, let bundleURL = newProcess.bundleURL else {
            XCTFail("The relaunched process was not found")
            return
        }

        let relaunchedApp = XCUIApplication(url: bundleURL)
        let dashboard = DashboardPage(app: relaunchedApp)
        dashboard.waitToLoad()

        let terminated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                // isTerminated is only a cached NSRunningApplication property
                // and remained stale in this flow. Query the actual PID.
                kill(originalProcess.processIdentifier, 0) != 0 && errno == ESRCH
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [terminated], timeout: 10),
            .completed,
            "old PID \(originalProcess.processIdentifier) at \(originalProcess.bundleURL?.path ?? "unknown") did not terminate; new PID is \(newProcess.processIdentifier)"
        )
        XCTAssertFalse(relaunchedApp.buttons["access.restart"].exists)
        relaunchedApp.terminate()
    }

    /// The installed app and the test app share a bundle identifier. The test
    /// target is the newest launch; after restart, the replacement is newest.
    private func newestSiftBarProcess() -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.andredias.siftbar")
            .max {
                ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
            }
    }
}
