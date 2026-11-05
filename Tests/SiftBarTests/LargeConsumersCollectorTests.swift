import Foundation
import XCTest
@testable import SiftBar

final class LargeConsumersCollectorTests: XCTestCase {
    func testRootsAreTheContentDirectories() {
        let roots = LargeConsumersCollector.roots(home: "/Users/tester")

        XCTAssertEqual(roots, [
            "/Users/tester/Downloads",
            "/Users/tester/Desktop",
            "/Users/tester/Documents",
            "/Users/tester/Movies",
            "/Users/tester/Pictures",
            "/Users/tester/Music"
        ])
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
        XCTAssertEqual(items.map(\.impactBytes), [8_000_000_000, 4_000_000_000])
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
