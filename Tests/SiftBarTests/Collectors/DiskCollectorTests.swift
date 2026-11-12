import XCTest
@testable import SiftBar

final class DiskCollectorTests: XCTestCase {
    func testRiskThresholds() {
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 0), .safe)
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 0.79), .safe)
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 0.7999), .safe)
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 0.80), .caution)
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 0.89), .caution)
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 0.90), .dangerous)
        XCTAssertEqual(DiskCollector.risk(forUsedRatio: 1.0), .dangerous)
    }

    func testReturnsNilWhenDiskIsUnavailable() {
        let disk = DiskStats(totalBytes: 0, usedBytes: 0, freeBytes: 0)

        XCTAssertNil(DiskCollector.item(for: disk))
    }

    func testBuildsDiskItemWithFreeSpaceImpact() throws {
        let disk = DiskStats(
            totalBytes: 100_000,
            usedBytes: 85_000,
            freeBytes: 15_000
        )

        let item = try XCTUnwrap(DiskCollector.item(for: disk))

        XCTAssertEqual(item.category, .disk)
        XCTAssertEqual(item.title, "Startup disk")
        XCTAssertEqual(item.impactBytes, 15_000)
        XCTAssertEqual(item.risk, .caution)
        XCTAssertEqual(item.action, .none)
        XCTAssertEqual(item.evidence, "df -k /System/Volumes/Data + volumeAvailableCapacityForImportantUsage")
        XCTAssertTrue(item.detail.contains("used of"))
        XCTAssertFalse(item.isInformational)
    }

    func testFullDiskIsDangerous() throws {
        let disk = DiskStats(totalBytes: 100, usedBytes: 95, freeBytes: 5)

        let item = try XCTUnwrap(DiskCollector.item(for: disk))

        XCTAssertEqual(item.risk, .dangerous)
    }

    func testHealthyDiskRowIsInformational() throws {
        let disk = DiskStats(totalBytes: 100, usedBytes: 40, freeBytes: 60)

        let item = try XCTUnwrap(DiskCollector.item(for: disk))

        XCTAssertEqual(item.risk, .safe)
        XCTAssertTrue(item.isInformational)
    }

    func testAvailableCapacityMatchesSystemSettingsWhenPresent() throws {
        let disk = DiskStats(
            totalBytes: 100_000,
            usedBytes: 60_000,
            freeBytes: 38_000,
            dataVolumeUsedBytes: 55_000,
            availableForImportantUsageBytes: 40_000,
            purgeableBytes: 2_000
        )

        let item = try XCTUnwrap(DiskCollector.item(for: disk))

        XCTAssertEqual(item.impactBytes, 40_000)
        XCTAssertEqual(disk.importantFreeBytes, 40_000)
        XCTAssertTrue(item.detail.contains("2,000 bytes") || item.detail.contains("2 KB") || item.detail.contains("purgeable"))
    }

    func testCollectReturnsOneItemForValidDisk() async {
        let collector = DiskCollector(
            disk: DiskStats(totalBytes: 100, usedBytes: 10, freeBytes: 90)
        )

        let items = await collector.collect()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .disk)
    }

    func testCollectReturnsEmptyForMissingDisk() async {
        let collector = DiskCollector(
            disk: DiskStats(totalBytes: 0, usedBytes: 0, freeBytes: 0)
        )

        let items = await collector.collect()

        XCTAssertTrue(items.isEmpty)
    }
}
