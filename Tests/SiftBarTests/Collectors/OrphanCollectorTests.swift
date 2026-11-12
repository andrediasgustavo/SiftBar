import Foundation
import XCTest
@testable import SiftBar

final class OrphanCollectorTests: XCTestCase {
    func testNormalizeStripsCasePunctuationAndSpaces() {
        XCTAssertEqual(OrphanCollector.normalize("Adobe Creative Cloud"), "adobecreativecloud")
        XCTAssertEqual(OrphanCollector.normalize("com.example.App-2"), "comexampleapp2")
        XCTAssertEqual(OrphanCollector.normalize(""), "")
    }

    func testMatchesExactAndPartialAppNames() {
        let installed = ["Google Chrome", "Visual Studio Code", "Slack"]

        XCTAssertTrue(OrphanCollector.hasMatchingApp(entry: "Google", installed: installed))
        XCTAssertTrue(OrphanCollector.hasMatchingApp(entry: "slack", installed: installed))
        XCTAssertTrue(OrphanCollector.hasMatchingApp(entry: "Visual Studio", installed: installed))
        XCTAssertTrue(OrphanCollector.hasMatchingApp(entry: "Code", installed: installed))
    }

    func testDoesNotMatchUnrelatedFolders() {
        let installed = ["Slack", "Google Chrome"]

        XCTAssertFalse(OrphanCollector.hasMatchingApp(entry: "RetroArch", installed: installed))
        XCTAssertFalse(OrphanCollector.hasMatchingApp(entry: "JetBrains", installed: installed))
    }

    func testShortFolderNamesAreTreatedAsOwned() {
        XCTAssertTrue(OrphanCollector.hasMatchingApp(entry: "ab", installed: []))
        XCTAssertTrue(OrphanCollector.hasMatchingApp(entry: "x", installed: []))
    }

    func testCandidatesSkipHiddenAndAppleFolders() {
        let entries = [".hidden", "com.apple.foo", "Adobe", "OrphanApp"]
        let installed = ["Adobe Creative Cloud"]

        let candidates = OrphanCollector.candidates(
            entries: entries,
            installed: installed,
            supportPath: "/tmp/Application Support"
        )

        XCTAssertEqual(candidates.map(\.name), ["OrphanApp"])
        XCTAssertEqual(candidates[0].path, "/tmp/Application Support/OrphanApp")
    }

    func testCandidatesKeepShortNamesOutOfResults() {
        let candidates = OrphanCollector.candidates(
            entries: ["ab"],
            installed: [],
            supportPath: "/tmp"
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testAppleAndCloudFoldersAreNeverLeftovers() {
        let entries = ["CloudDocs", "FileProvider", "Knowledge", "JetBrains"]

        let candidates = OrphanCollector.candidates(
            entries: entries,
            installed: [],
            supportPath: "/tmp"
        )

        XCTAssertEqual(candidates.map(\.name), ["JetBrains"])
        XCTAssertTrue(OrphanCollector.isSystemOwned("CloudDocs"))
        XCTAssertTrue(OrphanCollector.isSystemOwned("FileProvider"))
        XCTAssertFalse(OrphanCollector.isSystemOwned("JetBrains"))
    }

    func testItemsAreSortedBySizeAndLimited() {
        let measured = [
            OrphanCollector.Measured(
                candidate: .init(name: "Small", path: "/tmp/Small"),
                bytes: 200_000_000
            ),
            OrphanCollector.Measured(
                candidate: .init(name: "Large", path: "/tmp/Large"),
                bytes: 900_000_000
            ),
            OrphanCollector.Measured(
                candidate: .init(name: "Medium", path: "/tmp/Medium"),
                bytes: 500_000_000
            )
        ]

        let items = OrphanCollector.items(from: measured, limit: 2)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.title), [
            "Possible leftover: Large",
            "Possible leftover: Medium"
        ])
        XCTAssertEqual(items[0].risk, .caution)
        XCTAssertEqual(items[0].action, .trashLeftover(path: "/tmp/Large", bytes: 900_000_000))
        XCTAssertEqual(items[0].impactBytes, 900_000_000)
        XCTAssertEqual(items[0].evidence, "/tmp/Large")
        XCTAssertNotNil(items[0].warning)
        XCTAssertTrue(items[0].detail.contains("No app named Large is installed"))
        XCTAssertFalse(items[0].isInformational)
    }

    func testEmptyMeasuredListProducesNoItems() {
        XCTAssertTrue(OrphanCollector.items(from: []).isEmpty)
    }

    func testInstalledAppNamesReadsOnlyAppBundles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Sample.app"),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let names = OrphanCollector.installedAppNames(directories: [directory.path])

        XCTAssertEqual(names, ["Sample"])
    }
}
