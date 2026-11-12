import Foundation
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
        XCTAssertEqual(
            ItemAction.trashLeftover(path: "/tmp", bytes: 10),
            .trashLeftover(path: "/tmp", bytes: 10)
        )
        XCTAssertNotEqual(ItemAction.stopService(name: "redis"), .stopService(name: "nginx"))
    }

    func testReclaimDomainSeparatesDiskFromMemory() {
        let cache = ScanItem(
            category: .caches,
            title: "Cache",
            detail: "",
            impactLabel: "",
            impactBytes: 1,
            risk: .safe,
            action: .deletePath(path: "/tmp/cache", bytes: 1),
            evidence: ""
        )
        let leftover = ScanItem(
            category: .leftovers,
            title: "Leftover",
            detail: "",
            impactLabel: "",
            impactBytes: 1,
            risk: .caution,
            action: .trashLeftover(path: "/tmp/leftover", bytes: 1),
            evidence: ""
        )
        let process = ScanItem(
            category: .processes,
            title: "App",
            detail: "",
            impactLabel: "",
            impactBytes: 1,
            risk: .safe,
            action: .killProcess(pid: 42, name: "App"),
            evidence: ""
        )

        XCTAssertEqual(cache.reclaimDomain, .disk)
        XCTAssertEqual(leftover.reclaimDomain, .disk)
        XCTAssertEqual(process.reclaimDomain, .memory)
    }

    func testScanItemsDefaultToFindingsRatherThanInformationalRows() {
        let item = ScanItem(
            category: .disk,
            title: "Row",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: ""
        )

        XCTAssertFalse(item.isInformational)
        XCTAssertFalse(item.isProtected)
        XCTAssertFalse(item.isBreakdown)
    }

    func testMemoryStatsBreakdownDefaultsToZero() {
        let memory = MemoryStats(
            totalBytes: 100,
            usedBytes: 60,
            swapUsedBytes: 10,
            pressure: .normal
        )

        XCTAssertFalse(memory.hasBreakdown)
        XCTAssertEqual(memory.appBytes, 0)
        XCTAssertEqual(memory.cachedBytes, 0)
        XCTAssertEqual(memory.usedRatio, 0.6, accuracy: 0.0001)
    }

    func testDiskStatsUsesImportantCapacityWhenAvailable() {
        let disk = DiskStats(
            totalBytes: 100,
            usedBytes: 60,
            freeBytes: 38,
            dataVolumeUsedBytes: 50,
            availableForImportantUsageBytes: 40,
            purgeableBytes: 2
        )

        XCTAssertEqual(disk.importantFreeBytes, 40)
        XCTAssertEqual(disk.usedRatio, 0.6, accuracy: 0.0001)
        XCTAssertTrue(disk.hasContainerBreakdown)
    }

    func testDiskStatsFallsBackToStrictFreeSpace() {
        let disk = DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)

        XCTAssertEqual(disk.importantFreeBytes, 40)
        XCTAssertFalse(disk.hasContainerBreakdown)
    }

    func testRemovingItemsFiltersByIDAcrossCategories() {
        let cache = ScanItem(
            category: .caches,
            title: "Spotify cache",
            detail: "",
            impactLabel: "",
            impactBytes: 10,
            risk: .caution,
            action: .deletePath(path: "/tmp/spotify", bytes: 10),
            evidence: ""
        )
        let leftover = ScanItem(
            category: .leftovers,
            title: "Leftover",
            detail: "",
            impactLabel: "",
            impactBytes: 20,
            risk: .caution,
            action: .trashLeftover(path: "/tmp/leftover", bytes: 20),
            evidence: ""
        )
        let report = ScanReport(
            generatedAt: Date(),
            items: [cache, leftover],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )

        let pruned = report.removingItems(withIDs: [cache.id])

        XCTAssertEqual(pruned.items.map(\.id), [leftover.id])
        XCTAssertEqual(pruned.memory.totalBytes, 8)
        XCTAssertEqual(pruned.disk.totalBytes, 100)
    }

    func testReportDetectsAFailedSystemProbe() {
        let healthy = ScanReport(
            generatedAt: Date(),
            items: [],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )
        let failed = ScanReport(
            generatedAt: Date(),
            items: [],
            memory: MemoryStats(totalBytes: 0, usedBytes: 0, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 0, usedBytes: 0, freeBytes: 0)
        )

        XCTAssertFalse(healthy.failedToReadSystem)
        XCTAssertTrue(failed.failedToReadSystem)
    }

    func testRemovingItemsWithEmptySetKeepsReport() {
        let item = ScanItem(
            category: .caches,
            title: "Cache",
            detail: "",
            impactLabel: "",
            impactBytes: 1,
            risk: .safe,
            action: .deletePath(path: "/tmp/cache", bytes: 1),
            evidence: ""
        )
        let report = ScanReport(
            generatedAt: Date(),
            items: [item],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )

        XCTAssertEqual(report.removingItems(withIDs: []).items.map(\.id), [item.id])
    }

    func testRemovingItemsPrunesGroupedChildren() {
        let child = ScanItem(
            category: .processes,
            title: "Helper",
            detail: "",
            impactLabel: "",
            impactBytes: 5,
            risk: .caution,
            action: .killProcess(pid: 4242, name: "Helper"),
            evidence: ""
        )
        let parent = ScanItem(
            category: .processes,
            title: "App",
            detail: "",
            impactLabel: "",
            impactBytes: 10,
            risk: .caution,
            action: .killProcess(pid: 4241, name: "App"),
            evidence: "",
            children: [child]
        )
        let report = ScanReport(
            generatedAt: Date(),
            items: [parent],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )

        let prunedChild = report.removingItems(withIDs: [child.id])
        XCTAssertEqual(prunedChild.items.count, 1)
        XCTAssertTrue(prunedChild.items[0].children.isEmpty)
        XCTAssertEqual(prunedChild.items[0].id, parent.id)

        let prunedParent = report.removingItems(withIDs: [parent.id])
        XCTAssertTrue(prunedParent.items.isEmpty)
    }

    func testRemovingItemsByPathSurvivesRescanWithNewIDs() {
        // A rescan mints brand-new UUIDs, so ID matching alone cannot catch a
        // row that raced the Trash move. Path matching must remove it.
        let rescanned = ScanItem(
            category: .caches,
            title: "Spotify cache",
            detail: "",
            impactLabel: "",
            impactBytes: 10,
            risk: .caution,
            action: .deletePath(path: "/tmp/spotify", bytes: 10),
            evidence: ""
        )
        let other = ScanItem(
            category: .caches,
            title: "npm cache",
            detail: "",
            impactLabel: "",
            impactBytes: 5,
            risk: .safe,
            action: .deletePath(path: "/tmp/npm", bytes: 5),
            evidence: ""
        )
        let report = ScanReport(
            generatedAt: Date(),
            items: [rescanned, other],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )

        let pruned = report.removingItems(withIDs: [], paths: ["/tmp/spotify"])

        XCTAssertEqual(pruned.items.map { $0.title }, ["npm cache"])
    }

    func testTargetPathOnlyExistsForTrashActions() {
        XCTAssertEqual(
            ItemAction.deletePath(path: "/tmp/x", bytes: 1).targetPath,
            "/tmp/x"
        )
        XCTAssertEqual(
            ItemAction.trashLeftover(path: "/tmp/y", bytes: 1).targetPath,
            "/tmp/y"
        )
        XCTAssertNil(ItemAction.killProcess(pid: 1, name: "App").targetPath)
        XCTAssertNil(ItemAction.none.targetPath)
    }

    func testScanItemsDefaultToFastRefreshRows() {
        let item = ScanItem(
            category: .disk,
            title: "Row",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: ""
        )

        XCTAssertFalse(item.isSlowRefresh)
    }

    func testDisplayEvidenceUsesTheActionPathAndAbbreviatesHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = home + "/Library/Caches/com.example.app"
        let item = ScanItem(
            category: .caches,
            title: "Cache",
            detail: "",
            impactLabel: "",
            impactBytes: 1,
            risk: .safe,
            action: .deletePath(path: path, bytes: 1),
            evidence: "du -sk \(path)"
        )

        XCTAssertEqual(item.displayEvidence, "~/Library/Caches/com.example.app")
    }

    func testDisplayEvidenceKeepsCommandsWithoutAPath() {
        let item = ScanItem(
            category: .processes,
            title: "App",
            detail: "",
            impactLabel: "",
            impactBytes: 1,
            risk: .caution,
            action: .killProcess(pid: 1, name: "App"),
            evidence: "ps -Ao pid=,user=,rss=,comm="
        )

        XCTAssertEqual(item.displayEvidence, "ps -Ao pid=,user=,rss=,comm=")
    }

    func testDisplayEvidenceAbbreviatesLaunchItemDirectories() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let item = ScanItem(
            category: .startup,
            title: "com.example.agent",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: .safe,
            action: .disableLaunchItem(label: "com.example.agent"),
            evidence: home + "/Library/LaunchAgents"
        )

        XCTAssertEqual(item.displayEvidence, "~/Library/LaunchAgents")
    }

    func testMergingSlowItemsKeepsThePreviousSpaceMap() {
        let slow = ScanItem(
            category: .disk,
            title: "Caches",
            detail: "",
            impactLabel: "",
            impactBytes: 30,
            risk: .safe,
            action: .none,
            evidence: "",
            isInformational: true,
            isBreakdown: true,
            isSlowRefresh: true
        )
        let previous = ScanReport(
            generatedAt: Date(),
            items: [slow],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )
        let fresh = ScanItem(
            category: .caches,
            title: "npm cache",
            detail: "",
            impactLabel: "",
            impactBytes: 5,
            risk: .safe,
            action: .deletePath(path: "/tmp/npm", bytes: 5),
            evidence: ""
        )
        let quick = ScanReport(
            generatedAt: Date(),
            items: [fresh],
            memory: MemoryStats(totalBytes: 8, usedBytes: 4, swapUsedBytes: 0, pressure: .normal),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 50)
        )

        let merged = quick.mergingSlowItems(from: previous)

        XCTAssertEqual(merged.items.count, 2)
        XCTAssertTrue(merged.items.contains { $0.id == slow.id })
        XCTAssertTrue(merged.items.contains { $0.id == fresh.id })
        XCTAssertEqual(merged.disk.freeBytes, 50)
    }
}
