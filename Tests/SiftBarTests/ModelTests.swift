import XCTest
@testable import SiftBar

final class ModelTests: XCTestCase {
    func testRiskLabels() {
        XCTAssertEqual(Risk.safe.label, "Safe")
        XCTAssertEqual(Risk.caution.label, "Caution")
        XCTAssertEqual(Risk.dangerous.label, "Dangerous")
    }

    func testRiskRawValues() {
        XCTAssertEqual(Risk.safe.rawValue, "safe")
        XCTAssertEqual(Risk.caution.rawValue, "caution")
        XCTAssertEqual(Risk.dangerous.rawValue, "dangerous")
    }

    func testCategoryTitles() {
        XCTAssertEqual(ItemCategory.memory.title, "Memory")
        XCTAssertEqual(ItemCategory.processes.title, "Processes")
        XCTAssertEqual(ItemCategory.startup.title, "Startup")
        XCTAssertEqual(ItemCategory.services.title, "Services")
        XCTAssertEqual(ItemCategory.disk.title, "Disk")
        XCTAssertEqual(ItemCategory.caches.title, "Caches")
        XCTAssertEqual(ItemCategory.leftovers.title, "Leftovers")
    }

    func testCategorySymbolsAreNotEmpty() {
        for category in ItemCategory.allCases {
            XCTAssertFalse(category.symbol.isEmpty, "\(category) has no symbol")
        }
    }

    func testCategorySortOrderIsUniqueAndAscending() {
        let orders = ItemCategory.allCases.map(\.sortOrder)

        XCTAssertEqual(orders.count, Set(orders).count)
        XCTAssertEqual(orders, orders.sorted())
    }

    func testMemoryPressureRawValues() {
        XCTAssertEqual(MemoryPressure.normal.rawValue, "normal")
        XCTAssertEqual(MemoryPressure.warning.rawValue, "warning")
        XCTAssertEqual(MemoryPressure.critical.rawValue, "critical")
    }

    func testSnapshotEmptyValues() {
        let empty = SystemSnapshot.empty

        XCTAssertEqual(empty.totalMemoryBytes, 0)
        XCTAssertEqual(empty.freeDiskBytes, 0)
        XCTAssertEqual(empty.memory.usedBytes, 0)
        XCTAssertEqual(empty.memory.swapUsedBytes, 0)
        XCTAssertEqual(empty.memory.pressure, .normal)
        XCTAssertEqual(empty.disk.totalBytes, 0)
    }

    func testSnapshotConvenienceAccessors() {
        let snapshot = SystemSnapshot(
            memory: MemoryStats(
                totalBytes: 16,
                usedBytes: 8,
                swapUsedBytes: 2,
                pressure: .warning
            ),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )

        XCTAssertEqual(snapshot.totalMemoryBytes, 16)
        XCTAssertEqual(snapshot.freeDiskBytes, 40)
    }

    func testScanItemStoresAllFields() {
        let item = ScanItem(
            category: .caches,
            title: "Title",
            detail: "Detail",
            impactLabel: "1 MB",
            impactBytes: 1_048_576,
            risk: .caution,
            action: .deletePath(path: "/tmp/x", bytes: 1_048_576),
            evidence: "du -sk /tmp/x"
        )

        XCTAssertEqual(item.category, .caches)
        XCTAssertEqual(item.title, "Title")
        XCTAssertEqual(item.detail, "Detail")
        XCTAssertEqual(item.impactLabel, "1 MB")
        XCTAssertEqual(item.impactBytes, 1_048_576)
        XCTAssertEqual(item.risk, .caution)
        XCTAssertEqual(item.action, .deletePath(path: "/tmp/x", bytes: 1_048_576))
        XCTAssertEqual(item.evidence, "du -sk /tmp/x")
    }

    func testScanItemsGetUniqueIdentifiersByDefault() {
        let first = ScanItem(
            category: .disk,
            title: "A",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: ""
        )
        let second = ScanItem(
            category: .disk,
            title: "B",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: ""
        )

        XCTAssertNotEqual(first.id, second.id)
    }

    func testDangerousItemsAreNeverActionable() {
        let dangerous = ScanItem(
            category: .processes,
            title: "Protected",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .dangerous,
            action: .killProcess(pid: 1, name: "launchd"),
            evidence: ""
        )
        let safe = ScanItem(
            category: .caches,
            title: "Cache",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .deletePath(path: "/tmp/cache", bytes: 1),
            evidence: ""
        )
        let informational = ScanItem(
            category: .disk,
            title: "Disk",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: ""
        )

        XCTAssertFalse(dangerous.isActionable)
        XCTAssertTrue(safe.isActionable)
        XCTAssertFalse(informational.isActionable)
    }

    func testItemActionEquality() {
        XCTAssertEqual(ItemAction.none, .none)
        XCTAssertEqual(ItemAction.stopService(name: "redis"), .stopService(name: "redis"))
        XCTAssertEqual(
            ItemAction.killProcess(pid: 42, name: "App"),
            .killProcess(pid: 42, name: "App")
        )
        XCTAssertEqual(
            ItemAction.deletePath(path: "/tmp", bytes: 10),
            .deletePath(path: "/tmp", bytes: 10)
        )
        XCTAssertNotEqual(ItemAction.stopService(name: "redis"), .stopService(name: "nginx"))
    }
}
