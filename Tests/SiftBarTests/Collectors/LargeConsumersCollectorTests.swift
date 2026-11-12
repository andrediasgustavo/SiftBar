import Foundation
import XCTest
@testable import SiftBar

final class LargeConsumersCollectorTests: XCTestCase {
    func testRootsAreTheContentDirectories() {
        let roots = LargeConsumersCollector.roots(home: "/Users/tester")

        XCTAssertEqual(roots, [
            "/Users/tester/Downloads",
            "/Users/tester/Desktop",
            "/Users/tester/Documents"
        ])
    }

    func testRootsAreSkippedWithoutProtectedFolderAccess() {
        XCTAssertTrue(
            LargeConsumersCollector.roots(
                home: "/Users/tester",
                includeProtected: false
            ).isEmpty
        )
    }

    func testItemsAreSortedBySizeAndLimited() {
        let entries = [
            entry("Small", bytes: 1_000_000_000),
            entry("Huge", bytes: 8_000_000_000),
            entry("Medium", bytes: 4_000_000_000)
        ]

        let items = LargeConsumersCollector.items(from: entries, limit: 2)

        XCTAssertEqual(items.map(\.title), [
            "Large folder: Huge",
            "Large folder: Medium"
        ])
        XCTAssertEqual(items.map(\.impactBytes), [Int64(8_000_000_000), Int64(4_000_000_000)])
    }

    func testItemsBelowTheMinimumAreDropped() {
        let items = LargeConsumersCollector.items(from: [
            entry("Below", bytes: LargeConsumersCollector.minimumBytes - 1),
            entry("At threshold", bytes: LargeConsumersCollector.minimumBytes)
        ])

        XCTAssertEqual(items.map(\.title), ["Large folder: At threshold"])
    }

    func testItemsAreReadOnlyAndCaution() {
        let items = LargeConsumersCollector.items(from: [entry("Archive", bytes: 2_000_000_000)])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .disk)
        XCTAssertEqual(items[0].risk, .caution)
        XCTAssertEqual(items[0].action, .none)
        XCTAssertFalse(items[0].canBeChanged)
    }

    func testTitleDistinguishesFilesFromFolders() {
        let items = LargeConsumersCollector.items(from: [
            entry("Movie.mp4", bytes: 5_000_000_000, isDirectory: false)
        ])

        XCTAssertEqual(items[0].title, "Large file: Movie.mp4")
    }

    func testDetailAbbreviatesTheHomeDirectory() {
        let items = LargeConsumersCollector.items(
            from: [entry("Backups", bytes: 2_000_000_000)],
            home: "/Users/tester"
        )

        XCTAssertTrue(items[0].detail.contains("~/Documents/Backups"))
        XCTAssertFalse(items[0].detail.contains("/Users/tester"))
    }

    func testEvidenceIsThePathSoFinderCanRevealIt() {
        let items = LargeConsumersCollector.items(from: [entry("Backups", bytes: 2_000_000_000)])

        XCTAssertEqual(items[0].evidence, "/Users/tester/Documents/Backups")
        XCTAssertEqual(items[0].revealURL?.path, "/Users/tester/Documents/Backups")
    }

    func testAbbreviateOnlyRewritesRealHomeChildren() {
        XCTAssertEqual(
            LargeConsumersCollector.abbreviate("/Users/tester/Documents/A", home: "/Users/tester"),
            "~/Documents/A"
        )
        XCTAssertEqual(
            LargeConsumersCollector.abbreviate("/Users/tester-evil/Documents/A", home: "/Users/tester"),
            "/Users/tester-evil/Documents/A"
        )
        XCTAssertEqual(
            LargeConsumersCollector.abbreviate("/tmp/A", home: ""),
            "/tmp/A"
        )
    }

    /// End-to-end over a real directory: `du` runs, sizes are parsed, files and
    /// folders are distinguished, and the threshold is applied.
    func testCollectSizesRealChildrenWithDU() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let large = base.appendingPathComponent("large.bin")
        let small = base.appendingPathComponent("small.bin")
        try Data(repeating: 0xAB, count: 2_000_000).write(to: large)
        try Data(repeating: 0xCD, count: 1_000).write(to: small)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
        }

        let items = await LargeConsumersCollector().collect(
            roots: [base.path],
            home: base.path,
            minimumBytes: 1_000_000
        )

        XCTAssertEqual(items.map(\.title), ["Large file: large.bin"])
        XCTAssertEqual(items.first?.revealURL?.standardizedFileURL.path, large.standardizedFileURL.path)
    }

    // MARK: - Helpers

    private func entry(
        _ name: String,
        bytes: Int64,
        isDirectory: Bool = true
    ) -> LargeConsumersCollector.Entry {
        LargeConsumersCollector.Entry(
            path: "/Users/tester/Documents/\(name)",
            name: name,
            isDirectory: isDirectory,
            bytes: bytes
        )
    }
}
