import Foundation
import XCTest
@testable import SiftBar

final class ActionExecutorCommandTests: XCTestCase {
    private final class StubExecutor: CommandExecuting, @unchecked Sendable {
        struct Call: Equatable {
            let executable: String
            let arguments: [String]
            let timeout: TimeInterval
        }

        private let lock = NSLock()
        private var storage: [Call] = []
        private let handler: @Sendable (Call) -> Result<CommandResult, Error>

        init(handler: @escaping @Sendable (Call) -> Result<CommandResult, Error>) {
            self.handler = handler
        }

        var calls: [Call] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func run(
            _ executable: String,
            arguments: [String],
            timeout: TimeInterval
        ) async throws -> CommandResult {
            let call = Call(executable: executable, arguments: arguments, timeout: timeout)
            lock.lock()
            storage.append(call)
            lock.unlock()
            return try handler(call).get()
        }
    }

    private func simulatorItem(udid: String = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") -> ScanItem {
        ScanItem(
            category: .caches,
            title: "iPhone 16 Pro simulator",
            detail: "",
            impactLabel: "2 GB",
            impactBytes: 2_000_000_000,
            risk: .caution,
            action: .deleteSimulator(
                udid: udid,
                name: "iPhone 16 Pro",
                path: "/tmp/simulator",
                bytes: 2_000_000_000
            ),
            evidence: "/tmp/simulator"
        )
    }

    func testSimulatorDeletionUsesSIMCTLAndReportsFreedBytes() async {
        let executor = StubExecutor { _ in
            .success(CommandResult(stdout: "", stderr: "", exitCode: 0))
        }

        let report = await ActionExecutor.perform(simulatorItem(), executor: executor)

        XCTAssertTrue(report.success)
        XCTAssertTrue(report.message.contains("Deleted iPhone 16 Pro"))
        XCTAssertTrue(report.freesImmediately)
        XCTAssertFalse(report.movedToTrash)
        XCTAssertEqual(report.reclaimedBytes, 2_000_000_000)

        XCTAssertEqual(executor.calls, [
            .init(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "delete", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"],
                timeout: 30
            )
        ])
    }

    func testSimulatorFailureSurfacesStderr() async {
        let executor = StubExecutor { _ in
            .success(CommandResult(stdout: "", stderr: "Unable to delete device", exitCode: 1))
        }

        let report = await ActionExecutor.perform(simulatorItem(), executor: executor)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.message.contains("Unable to delete device"))
        XCTAssertEqual(report.reclaimedBytes, 0)
        XCTAssertTrue(report.freesImmediately)
    }

    func testInvalidSimulatorUUIDNeverReachesTheExecutor() async {
        let executor = StubExecutor { _ in
            XCTFail("the executor must not run for an invalid UUID")
            return .success(CommandResult(stdout: "", stderr: "", exitCode: 0))
        }

        let report = await ActionExecutor.perform(simulatorItem(udid: "not-a-uuid"), executor: executor)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.message.contains("not a simulator identifier"))
        XCTAssertTrue(executor.calls.isEmpty)
    }

    func testUnavailableSimulatorsUseTheFixedSIMCTLCommand() async {
        let item = ScanItem(
            category: .caches,
            title: "Unavailable simulators",
            detail: "",
            impactLabel: "1 GB",
            impactBytes: 1_000_000_000,
            risk: .safe,
            action: .deleteUnavailableSimulators(count: 3),
            evidence: "xcrun simctl delete unavailable"
        )
        let executor = StubExecutor { _ in
            .success(CommandResult(stdout: "", stderr: "", exitCode: 0))
        }

        let report = await ActionExecutor.perform(item, executor: executor)

        XCTAssertTrue(report.success)
        XCTAssertTrue(report.freesImmediately)
        XCTAssertEqual(executor.calls, [
            .init(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "delete", "unavailable"],
                timeout: 60
            )
        ])
    }
}
