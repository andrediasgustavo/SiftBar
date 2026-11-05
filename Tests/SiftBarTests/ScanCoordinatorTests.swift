import XCTest
@testable import SiftBar

final class ScanCoordinatorTests: XCTestCase {
    private func item(
        category: ItemCategory,
        title: String,
        impact: Int64?,
        risk: Risk = .safe
    ) -> ScanItem {
        ScanItem(
            category: category,
            title: title,
            detail: "",
            impactLabel: "",
            impactBytes: impact,
            risk: risk,
            action: .none,
            evidence: ""
        )
    }

    func testSortGroupsItemsByCategoryOrder() {
        let items = [
            item(category: .leftovers, title: "Leftover", impact: 10),
            item(category: .memory, title: "Memory", impact: nil),
            item(category: .caches, title: "Cache", impact: 20),
            item(category: .disk, title: "Disk", impact: 30)
        ]

        let sorted = ScanCoordinator.sort(items)

        XCTAssertEqual(sorted.map(\.category), [.memory, .disk, .caches, .leftovers])
    }

    func testSortOrdersByImpactWithinCategory() {
        let items = [
            item(category: .caches, title: "Small", impact: 10),
            item(category: .caches, title: "Large", impact: 1_000),
            item(category: .caches, title: "Medium", impact: 100)
        ]

        let sorted = ScanCoordinator.sort(items)

        XCTAssertEqual(sorted.map(\.title), ["Large", "Medium", "Small"])
    }

    func testItemsWithoutImpactSortAfterItemsWithImpact() {
        let items = [
            item(category: .processes, title: "No impact", impact: nil),
            item(category: .processes, title: "Has impact", impact: 1)
        ]

        let sorted = ScanCoordinator.sort(items)

        XCTAssertEqual(sorted.map(\.title), ["Has impact", "No impact"])
    }

    func testTiesAreBrokenAlphabeticallyCaseInsensitively() {
        let items = [
            item(category: .startup, title: "beta", impact: 100),
            item(category: .startup, title: "Alpha", impact: 100),
            item(category: .startup, title: "gamma", impact: 100)
        ]

        let sorted = ScanCoordinator.sort(items)

        XCTAssertEqual(sorted.map(\.title), ["Alpha", "beta", "gamma"])
    }

    func testSortIsStableForEmptyInput() {
        XCTAssertTrue(ScanCoordinator.sort([]).isEmpty)
    }

    func testSortDoesNotDropOrDuplicateItems() {
        let items = [
            item(category: .memory, title: "A", impact: nil),
            item(category: .disk, title: "B", impact: 3),
            item(category: .caches, title: "C", impact: 2)
        ]

        let sorted = ScanCoordinator.sort(items)

        XCTAssertEqual(sorted.count, items.count)
        XCTAssertEqual(Set(sorted.map(\.title)), Set(items.map(\.title)))
    }

    func testRunProducesARealSortedReport() async {
        let report = await ScanCoordinator.run()

        XCTAssertFalse(report.items.isEmpty)
        XCTAssertEqual(report.items, ScanCoordinator.sort(report.items))
        XCTAssertGreaterThan(report.memory.totalBytes, 0)
        XCTAssertGreaterThan(report.disk.totalBytes, 0)
        XCTAssertTrue(report.items.allSatisfy { !$0.title.isEmpty })
    }
}
