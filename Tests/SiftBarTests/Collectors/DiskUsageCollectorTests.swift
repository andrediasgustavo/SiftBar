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

    func testSystemOtherDrilldownNamesPartsInsideTheRemainder() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 50 * gigabyte, freeBytes: 50 * gigabyte)
        var sizes = sizes()
        sizes.remainderDetails = [
            .init(name: "Trash", bytes: 4 * gigabyte, detail: "", evidence: "du -sk ~/.Trash", revealPath: nil),
            .init(name: "Homebrew", bytes: 6 * gigabyte, detail: "", evidence: "du -sk /opt/homebrew", revealPath: nil)
        ]

        let category = DiskUsageCollector.categories(sizes: sizes, disk: disk)
            .first { $0.name == "System & other" }

        XCTAssertEqual(category?.bytes, 20 * gigabyte)
        XCTAssertEqual(category?.children.map(\.title), ["Homebrew", "Trash", "Other macOS and protected data"])
        XCTAssertEqual(category?.children.map(\.impactBytes), [6 * gigabyte, 4 * gigabyte, 10 * gigabyte])
    }

    func testRemainderDrilldownNeverExceedsTheRemainder() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 50 * gigabyte, freeBytes: 50 * gigabyte)
        var sizes = sizes()
        sizes.remainderDetails = [
            .init(name: "Trash", bytes: 25 * gigabyte, detail: "", evidence: "", revealPath: nil)
        ]

        let category = DiskUsageCollector.categories(sizes: sizes, disk: disk)
            .first { $0.name == "System & other" }

        // The category does not fit: it must be left in the unaccounted row
        // rather than making the children add up to more than the parent.
        XCTAssertEqual(category?.children.map(\.title), ["Other macOS and protected data"])
        XCTAssertEqual(category?.children.first?.impactBytes, 20 * gigabyte)
        XCTAssertLessThanOrEqual(
            category?.children.compactMap(\.impactBytes).reduce(0, +) ?? 0,
            20 * gigabyte
        )
    }

    func testSnapshotsAreShownAsManagedByMacOS() {
        let disk = DiskStats(totalBytes: 100 * gigabyte, usedBytes: 50 * gigabyte, freeBytes: 50 * gigabyte)
        var sizes = sizes()
        sizes.remainderDetails = DiskUsageCollector.remainderDetails(
            from: ["trash": 2 * gigabyte],
            snapshotCount: 3
        )

        let category = DiskUsageCollector.categories(sizes: sizes, disk: disk)
            .first { $0.name == "System & other" }
        let snapshot = category?.children.first { $0.title == "Local snapshots" }

        XCTAssertEqual(snapshot?.impactLabel, "macOS-managed")
        XCTAssertNil(snapshot?.impactBytes)
        XCTAssertTrue(snapshot?.detail.contains("3 APFS local snapshots") == true)
    }

    func testRemainderChildrenAreReadOnly() {
        let items = DiskUsageCollector.remainderChildren(
            details: [
                .init(name: "Trash", bytes: 2 * gigabyte, detail: "", evidence: "", revealPath: "~/.Trash")
            ],
            remainder: 5 * gigabyte
        )

        XCTAssertTrue(items.allSatisfy { $0.action == .none })
        XCTAssertTrue(items.allSatisfy(\.isInformational))
        XCTAssertTrue(items.allSatisfy(\.isBreakdown))
        XCTAssertFalse(items.contains { $0.canBeChanged })
    }

    func testRemainderDetailsSkipEmptyPaths() {
        let details = DiskUsageCollector.remainderDetails(
            from: ["trash": 0, "homebrew": 2 * gigabyte],
            snapshotCount: 0
        )

        XCTAssertEqual(details.map(\.name), ["Homebrew"])
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
