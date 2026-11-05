import Foundation
import XCTest
@testable import SiftBar

final class StartupCollectorTests: XCTestCase {
    func testParsesFailingThirdPartyLaunchItems() {
        let output = """
        PID	Status	Label
        -	0	com.apple.healthy
        123	-	com.example.loaded
        456	1	com.example.failing
        789	-9	com.example.killed
        """

        let items = StartupCollector.parseFailingItems(output)

        XCTAssertEqual(items.map(\.title), [
            "Failing launch item: com.example.failing",
            "Failing launch item: com.example.killed"
        ])
        XCTAssertTrue(items.allSatisfy { $0.risk == .caution })
        XCTAssertTrue(items.allSatisfy { $0.category == .startup })
        XCTAssertEqual(items.first?.impactLabel, "exit 1")
    }

    func testSkipsAppleAgentsAndHeader() {
        let output = """
        PID	Status	Label
        1	-9	com.apple.cloudphotod
        2	-	com.apple.homed
        """

        XCTAssertTrue(StartupCollector.parseFailingItems(output).isEmpty)
    }

    func testSkipsZeroAndDashStatuses() {
        let output = """
        PID	Status	Label
        1	0	com.example.ok
        2	-	com.example.ondemand
        """

        XCTAssertTrue(StartupCollector.parseFailingItems(output).isEmpty)
    }

    func testSkipsMalformedLaunchctlLines() {
        let output = """
        PID	Status	Label
        too	few
        3	1	com.example.valid
        """

        let items = StartupCollector.parseFailingItems(output)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Failing launch item: com.example.valid")
    }

    func testRespectsFailingItemLimit() {
        var output = "PID\tStatus\tLabel\n"
        for index in 0..<20 {
            output += "\(index)\t1\tcom.example.fail\(index)\n"
        }

        let items = StartupCollector.parseFailingItems(output)

        XCTAssertEqual(items.count, StartupCollector.failingLimit)
    }

    func testLaunchItemsIgnoreAppleAndHiddenAndNonPlistFiles() throws {
        let directory = try makeTemporaryDirectory()
        try writeFile(named: "com.example.agent.plist", in: directory)
        try writeFile(named: "com.apple.system.plist", in: directory)
        try writeFile(named: "notes.txt", in: directory)

        let items = StartupCollector.launchItems(in: [directory.path])

        XCTAssertEqual(items.map(\.title), ["Launch item: com.example.agent"])
        XCTAssertEqual(items[0].evidence, directory.path)
        XCTAssertEqual(items[0].impactLabel, "launch agent")
        XCTAssertEqual(items[0].risk, .safe)
    }

    func testLaunchItemsDeduplicateLabelsAcrossDirectories() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        try writeFile(named: "com.example.duplicate.plist", in: first)
        try writeFile(named: "com.example.duplicate.plist", in: second)
        try writeFile(named: "com.example.second.plist", in: second)

        let items = StartupCollector.launchItems(in: [first.path, second.path])

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.title)).count, 2)
    }

    func testLaunchItemsRespectTheLimit() throws {
        let directory = try makeTemporaryDirectory()
        for index in 0..<5 {
            try writeFile(named: "com.example.agent\(index).plist", in: directory)
        }

        let items = StartupCollector.launchItems(in: [directory.path], limit: 2)

        XCTAssertEqual(items.count, 2)
    }

    func testLaunchItemsHandleMissingDirectories() {
        let items = StartupCollector.launchItems(in: ["/definitely/not/a/real/directory"])

        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeFile(named name: String, in directory: URL) throws {
        try Data("test".utf8).write(to: directory.appendingPathComponent(name))
    }
}
