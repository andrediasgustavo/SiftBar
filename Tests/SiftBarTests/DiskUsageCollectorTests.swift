import XCTest
@testable import SiftBar

final class DiskUsageCollectorTests: XCTestCase {
    private let gigabyte: Int64 = 1_000_000_000

    private func sizes() -> DiskUsageCollector.Sizes {
        DiskUsageCollector.Sizes(
            home: [
                "Documents": 5 * gigabyte,
                "Projetos": 1 * gigabyte,
                "Library": 20 * gigabyte,
                ".android": 1 * gigabyte,
                ".gradle": 1 * gigabyte
            ],
            library: [
                "Application Support": 2 * gigabyte,
                "Caches": 3 * gigabyte,
                "Developer": 4 * gigabyte,
                "Containers": 1 * gigabyte
            ],
            applications: 10 * gigabyte,
            systemLibrary: 2 * gigabyte
        )
    }

    func testGroupsMeasuredFoldersAndDerivesTheRemainder() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 50 * gigabyte, freeBytes: 50 * gigabyte)

        let categories = DiskUsageCollector.categories(sizes: sizes(), disk: disk)
        let byName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.bytes) })

        XCTAssertEqual(byName["Applications"], 10 * gigabyte)
        XCTAssertEqual(byName["Documents & media"], 5 * gigabyte)
        XCTAssertEqual(byName["Developer"], 6 * gigabyte)
        XCTAssertEqual(byName["App data"], 3 * gigabyte)
        XCTAssertEqual(byName["Caches"], 3 * gigabyte)
        XCTAssertEqual(byName["Other user folders"], 1 * gigabyte)
        XCTAssertEqual(byName["System-wide data"], 2 * gigabyte)
        XCTAssertEqual(byName["System & other"], 20 * gigabyte)
    }

    func testRemainderIsNeverNegative() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 10 * gigabyte, freeBytes: 90 * gigabyte)

        let categories = DiskUsageCollector.categories(sizes: sizes(), disk: disk)

        XCTAssertNil(categories.first { $0.name == "System & other" })
    }

    func testItemsAreInformationalBreakdownRows() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 50 * gigabyte, freeBytes: 50 * gigabyte)

        let items = DiskUsageCollector.items(sizes: sizes(), disk: disk)

        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.category == .disk })
        XCTAssertTrue(items.allSatisfy(\.isInformational))
        XCTAssertTrue(items.allSatisfy(\.isBreakdown))
        XCTAssertTrue(items.allSatisfy { $0.action == .none })
        XCTAssertEqual(items.first?.title, "System & other")
    }

    func testSmallCategoriesAreFilteredOut() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 50 * gigabyte, freeBytes: 50 * gigabyte)
        var sizes = sizes()
        sizes.library["Caches"] = 10 * 1_000_000

        let categories = DiskUsageCollector.categories(sizes: sizes, disk: disk)

        XCTAssertNil(categories.first { $0.name == "Caches" })
    }

    func testOptionalSizeSkipsProtectedFoldersWhenDisabled() async {
        let value = await DiskUsageCollector.optionalSize(
            of: "/Users",
            include: false,
            timeout: 5
        )

        XCTAssertNil(value)
    }
}
