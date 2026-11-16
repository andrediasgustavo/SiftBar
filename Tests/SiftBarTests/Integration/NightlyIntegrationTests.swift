import Foundation
import XCTest
@testable import SiftBar

/// Destructive, real-process checks. They are skipped unless the nightly
/// workflow sets SIFTBAR_NIGHTLY=1, so a normal `scripts/test.sh` on a
/// developer Mac never creates or deletes anything.
final class NightlyIntegrationTests: XCTestCase {
    private var isNightly: Bool {
        ProcessInfo.processInfo.environment["SIFTBAR_NIGHTLY"] == "1"
    }

    func testSimulatorCreateAndDeleteThroughSIMCTL() async throws {
        guard isNightly else { return }

        guard let runtime = await firstAvailableRuntime(),
              let deviceType = await firstIPhoneDeviceType() else {
            // GitHub macOS runners do not always ship a simulator runtime.
            // The action path is still covered by the injected executor and
            // the confirmation UI tests; surface the skip as a warning.
            print("::warning title=Nightly simulator skipped::no available simulator runtime or iPhone device type")
            return
        }
        let name = "SiftBar Nightly \(UUID().uuidString.prefix(8))"

        let created = try await CommandRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "create", name, deviceType, runtime],
            timeout: 30
        )
        guard created.exitCode == 0 else {
            print("::warning title=Nightly simulator skipped::could not create a simulator: \(created.stderr)")
            return
        }

        let udid = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: udid) != nil else {
            XCTFail("simctl returned an unexpected identifier: \(udid)")
            return
        }

        defer { runSync("/usr/bin/xcrun", ["simctl", "delete", udid]) }
        addTeardownBlock { [udid] in
            self.runSync("/usr/bin/xcrun", ["simctl", "delete", udid])
        }

        let item = ScanItem(
            category: .caches,
            title: "\(name) simulator",
            detail: "",
            impactLabel: "0 B",
            impactBytes: 0,
            risk: .caution,
            action: .deleteSimulator(
                udid: udid,
                name: name,
                path: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Developer/CoreSimulator/Devices/\(udid)/data",
                bytes: 0
            ),
            evidence: "nightly"
        )

        let report = await ActionExecutor.perform(item)
        XCTAssertTrue(report.success, report.message)

        let listed = try await CommandRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "-j"],
            timeout: 15
        )
        XCTAssertFalse(listed.stdout.contains(udid), "the temporary simulator is still registered")
    }

    func testCacheIsMovedToTrashByTheRealExecutor() async throws {
        guard isNightly else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directory = URL(fileURLWithPath: "\(home)/Library/Caches/SiftBar-Nightly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 4_096)
            .write(to: directory.appendingPathComponent("payload.bin"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let item = ScanItem(
            category: .caches,
            title: "Nightly cache",
            detail: "",
            impactLabel: "4 KB",
            impactBytes: 4_096,
            risk: .safe,
            action: .deletePath(path: directory.path, bytes: 4_096),
            evidence: directory.path
        )

        let report = await ActionExecutor.perform(item)

        XCTAssertTrue(report.success, report.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLeftoverIsMovedToTrashByTheRealExecutor() async throws {
        guard isNightly else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directory = URL(fileURLWithPath: "\(home)/Library/Application Support/SiftBar-Nightly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 4_096)
            .write(to: directory.appendingPathComponent("payload.bin"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let item = ScanItem(
            category: .leftovers,
            title: "Nightly leftover",
            detail: "",
            impactLabel: "4 KB",
            impactBytes: 4_096,
            risk: .caution,
            action: .trashLeftover(path: directory.path, bytes: 4_096),
            evidence: directory.path,
            leftoverConfidence: .high
        )

        let report = await ActionExecutor.perform(item)

        XCTAssertTrue(report.success, report.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    // MARK: - simulator metadata

    private struct RuntimePayload: Decodable {
        struct Runtime: Decodable {
            let identifier: String
            let isAvailable: Bool?
        }

        let runtimes: [Runtime]
    }

    private struct DeviceTypePayload: Decodable {
        struct DeviceType: Decodable {
            let identifier: String
            let name: String
        }

        let devicetypes: [DeviceType]
    }

    private func firstAvailableRuntime() async -> String? {
        guard let result = try? await CommandRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "runtimes", "-j"],
            timeout: 15
        ), result.exitCode == 0,
        let payload = try? JSONDecoder().decode(RuntimePayload.self, from: Data(result.stdout.utf8)) else {
            return nil
        }

        // simctl lists runtimes in ascending order; the newest generic iOS
        // runtime supports the newest iPhone device type. The special
        // `iOS-27-2-iPhone19-4` runtime is tied to one device and must be
        // skipped.
        return payload.runtimes
            .filter { $0.isAvailable == true && !$0.identifier.contains("iPhone") }
            .last?
            .identifier
    }

    private func firstIPhoneDeviceType() async -> String? {
        guard let result = try? await CommandRunner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devicetypes", "-j"],
            timeout: 15
        ), result.exitCode == 0,
        let payload = try? JSONDecoder().decode(DeviceTypePayload.self, from: Data(result.stdout.utf8)) else {
            return nil
        }

        return payload.devicetypes.first(where: { $0.name.contains("iPhone") })?.identifier
    }

    private func runSync(_ executable: String, _ arguments: [String]) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            _ = try? await CommandRunner.run(executable, arguments: arguments, timeout: 15)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)
    }
}
