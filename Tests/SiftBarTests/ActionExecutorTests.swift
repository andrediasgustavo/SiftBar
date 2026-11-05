import Foundation
import XCTest
@testable import SiftBar

final class ActionExecutorTests: XCTestCase {
    func testPreviewForKillProcess() {
        XCTAssertEqual(
            ActionExecutor.preview(for: .killProcess(pid: 42, name: "Foo")),
            "kill -TERM 42    # Foo"
        )
    }

    func testPreviewForDisableLaunchItem() {
        let preview = ActionExecutor.preview(for: .disableLaunchItem(label: "com.example.agent"))

        XCTAssertTrue(preview.contains("launchctl bootout gui/"))
        XCTAssertTrue(preview.contains("launchctl disable gui/"))
        XCTAssertTrue(preview.contains("com.example.agent"))
    }

    func testPreviewForEnableLaunchItem() {
        let preview = ActionExecutor.preview(for: .enableLaunchItem(label: "com.example.agent"))

        XCTAssertTrue(preview.contains("launchctl enable gui/"))
        XCTAssertTrue(preview.contains("com.example.agent"))
    }

    func testPreviewForEnableLaunchItemIncludesPlistPath() throws {
        let directory = try makeTemporaryDirectory()
        let plist = directory.appendingPathComponent("com.example.agent.plist")
        try Data("test".utf8).write(to: plist)

        let item = item(
            action: .enableLaunchItem(label: "com.example.agent"),
            evidence: directory.path
        )

        let preview = ActionExecutor.preview(for: item)

        XCTAssertTrue(preview.contains("launchctl enable gui/"))
        XCTAssertTrue(preview.contains(plist.path))
    }

    func testEnableVerbAndTitle() {        let item = item(action: .enableLaunchItem(label: "com.example.agent"))

        XCTAssertEqual(ActionExecutor.verb(for: item.action), "Enable")
        XCTAssertEqual(ActionExecutor.title(for: [item]), "Enable Launch Item…")
    }

    func testEnableLaunchItemIsChangeableOnlyForUserAgents() {
        let user = item(
            action: .enableLaunchItem(label: "com.example.user"),
            evidence: "/Users/tester/Library/LaunchAgents"
        )
        let system = item(
            action: .enableLaunchItem(label: "com.example.system"),
            evidence: "/Library/LaunchDaemons"
        )

        XCTAssertTrue(user.canBeChanged)
        XCTAssertFalse(system.canBeChanged)
    }

    func testPreviewForStopService() {        XCTAssertEqual(
            ActionExecutor.preview(for: .stopService(name: "postgresql")),
            "brew services stop postgresql"
        )
    }

    func testPreviewForDeletePath() {
        XCTAssertEqual(
            ActionExecutor.preview(for: .deletePath(path: "/tmp/cache", bytes: 10)),
            "Move to Trash: /tmp/cache"
        )
    }

    func testPreviewForNoAction() {
        XCTAssertEqual(ActionExecutor.preview(for: .none), "No action")
    }

    func testVerbsMatchTheAction() {
        XCTAssertEqual(ActionExecutor.verb(for: .killProcess(pid: 1, name: "Foo")), "Quit")
        XCTAssertEqual(ActionExecutor.verb(for: .disableLaunchItem(label: "x")), "Disable")
        XCTAssertEqual(ActionExecutor.verb(for: .stopService(name: "x")), "Stop")
        XCTAssertEqual(ActionExecutor.verb(for: .deletePath(path: "/tmp/x", bytes: 0)), "Move to Trash")
        XCTAssertEqual(ActionExecutor.verb(for: .none), "Change")
    }

    func testTitlesForOneAndManyActions() {
        let one = item(action: .killProcess(pid: 1, name: "Foo"))
        let two = item(action: .killProcess(pid: 2, name: "Bar"))

        XCTAssertEqual(ActionExecutor.title(for: [one]), "Quit Process…")
        XCTAssertEqual(ActionExecutor.title(for: [one, two]), "Apply 2 Actions…")
        XCTAssertEqual(ActionExecutor.sheetTitle(for: [one]), "Review 1 Action")
        XCTAssertEqual(ActionExecutor.sheetTitle(for: [one, two]), "Review 2 Actions")
    }

    func testLibraryLaunchItemsRequireAdmin() {
        let system = item(
            action: .disableLaunchItem(label: "com.example.system"),
            evidence: "/Library/LaunchDaemons"
        )
        let user = item(
            action: .disableLaunchItem(label: "com.example.user"),
            evidence: "/Users/tester/Library/LaunchAgents"
        )

        XCTAssertTrue(system.requiresAdmin)
        XCTAssertFalse(user.requiresAdmin)
    }

    func testRequiresAdminOnlyAppliesToLaunchItems() {
        let process = item(
            action: .killProcess(pid: 42, name: "Foo"),
            evidence: "/Library/LaunchDaemons"
        )

        XCTAssertFalse(process.requiresAdmin)
    }

    func testCanBeChangedRejectsDangerousAndNoActionItems() {
        XCTAssertTrue(item(action: .killProcess(pid: 42, name: "Foo")).canBeChanged)
        XCTAssertFalse(item(action: .killProcess(pid: 42, name: "Foo"), risk: .dangerous).canBeChanged)
        XCTAssertFalse(item(action: .none).canBeChanged)
        XCTAssertFalse(item(
            action: .disableLaunchItem(label: "x"),
            evidence: "/Library/LaunchDaemons"
        ).canBeChanged)
    }

    func testSystemCachesRequireAdmin() {
        let system = item(action: .deletePath(path: "/Library/Developer/CoreSimulator/Caches", bytes: 1))
        let user = item(action: .deletePath(path: "/Users/tester/Library/Caches", bytes: 1))

        XCTAssertTrue(system.requiresAdmin)
        XCTAssertFalse(system.canBeChanged)
        XCTAssertFalse(user.requiresAdmin)
        XCTAssertTrue(user.canBeChanged)
    }

    func testDeletePathOutsideTheWhitelistIsRefused() async {
        let report = await ActionExecutor.perform(
            item(action: .deletePath(path: "/tmp/siftbar-not-whitelisted", bytes: 1))
        )

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.reclaimedBytes, 0)
        XCTAssertTrue(report.message.contains("whitelist"))
    }

    func testRevealURLUsesTheDeletePath() {
        let item = item(action: .deletePath(path: "/tmp/example-cache", bytes: 10))

        XCTAssertEqual(item.revealURL?.path, "/tmp/example-cache")
    }

    func testRevealURLResolvesTheLaunchItemPlist() throws {
        let directory = try makeTemporaryDirectory()
        let plist = directory.appendingPathComponent("com.example.agent.plist")
        try Data("test".utf8).write(to: plist)

        let item = item(
            action: .disableLaunchItem(label: "com.example.agent"),
            evidence: directory.path
        )

        XCTAssertEqual(item.revealURL?.path, plist.path)
    }

    func testRevealURLFallsBackToTheLaunchDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let item = item(
            action: .disableLaunchItem(label: "com.example.missing"),
            evidence: directory.path
        )

        XCTAssertEqual(item.revealURL?.path, directory.path)
    }

    func testRevealURLIgnoresCommandEvidence() {
        XCTAssertNil(item(action: .killProcess(pid: 1, name: "Foo"), evidence: "ps -Ao pid,user,rss,comm").revealURL)
        XCTAssertNil(item(action: .none, evidence: "memory_pressure").revealURL)
    }

    func testRevealURLUsesAPathForReadOnlyItems() {
        let item = item(action: .none, evidence: "/Users/tester/Library/Application Support/Example")

        XCTAssertEqual(item.revealURL?.path, "/Users/tester/Library/Application Support/Example")
    }

    func testActionReportOnlyCountsReclaimedBytesOnSuccess() {
        let success = ActionReport(item: item(action: .killProcess(pid: 1, name: "Foo"), impactBytes: 1_000), success: true, message: "")
        let failure = ActionReport(item: item(action: .killProcess(pid: 1, name: "Foo"), impactBytes: 1_000), success: false, message: "")
        let noBytes = ActionReport(item: item(action: .none), success: true, message: "")

        XCTAssertEqual(success.reclaimedBytes, 1_000)
        XCTAssertEqual(failure.reclaimedBytes, 0)
        XCTAssertEqual(noBytes.reclaimedBytes, 0)
    }

    func testPerformNoActionFailsGracefully() async {
        let report = await ActionExecutor.perform(item(action: .none))

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.reclaimedBytes, 0)
    }

    // MARK: - Helpers

    private func item(
        action: ItemAction,
        risk: Risk = .safe,
        evidence: String = "/tmp/example",
        impactBytes: Int64? = nil
    ) -> ScanItem {
        ScanItem(
            category: .startup,
            title: "Example",
            detail: "Detail",
            impactLabel: "1 MB",
            impactBytes: impactBytes,
            risk: risk,
            action: action,
            evidence: evidence
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
