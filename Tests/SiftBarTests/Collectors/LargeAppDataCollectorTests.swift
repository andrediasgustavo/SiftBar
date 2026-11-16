import Foundation
import XCTest
@testable import SiftBar

final class LargeAppDataCollectorTests: XCTestCase {
    private func measured(_ name: String, _ bytes: Int64) -> LargeAppDataCollector.Measured {
        LargeAppDataCollector.Measured(
            candidate: .init(
                name: name,
                path: "/Users/test/Library/\(name)",
                detail: "Detail"
            ),
            bytes: bytes
        )
    }

    func testCandidatesCoverKnownLargeAppData() {
        let candidates = LargeAppDataCollector.candidates(home: "/Users/test")
        let names = candidates.map(\.name)

        XCTAssertTrue(names.contains("Docker disk image"))
        XCTAssertTrue(names.contains("iPhone backups"))
        XCTAssertTrue(names.contains("Xcode build archives"))
        XCTAssertTrue(candidates.allSatisfy { $0.path.hasPrefix("/Users/test/Library") })
    }

    func testItemsAreReadOnlyAndSortedBySize() {
        let items = LargeAppDataCollector.items(from: [
            measured("Small", 1_000_000_000),
            measured("Large", 5_000_000_000),
            measured("Medium", 2_000_000_000)
        ])

        XCTAssertEqual(items.map(\.title), ["Large", "Medium", "Small"])
        XCTAssertTrue(items.allSatisfy { $0.action == .none })
        XCTAssertTrue(items.allSatisfy(\.isInformational))
        XCTAssertTrue(items.allSatisfy(\.isSlowRefresh))
        XCTAssertTrue(items.allSatisfy { $0.revealURL != nil })
        XCTAssertFalse(items.contains { $0.canBeChanged })
        XCTAssertTrue(items.first?.detail.contains("not a cache") == true)
    }

    func testLimitKeepsTheLargestItems() {
        let items = LargeAppDataCollector.items(
            from: (1...10).map { measured("Item \($0)", Int64($0) * 1_000_000_000) },
            limit: 3
        )

        XCTAssertEqual(items.map(\.title), ["Item 10", "Item 9", "Item 8"])
    }
}
