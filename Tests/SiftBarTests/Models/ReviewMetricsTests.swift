import XCTest
@testable import SiftBar

final class ReviewMetricsTests: XCTestCase {
    private func item(
        category: ItemCategory,
        action: ItemAction,
        bytes: Int64,
        risk: Risk = .safe,
        informational: Bool = false
    ) -> ScanItem {
        ScanItem(
            category: category,
            title: "Item",
            detail: "",
            impactLabel: "\(bytes)",
            impactBytes: bytes,
            risk: risk,
            action: action,
            evidence: "",
            isInformational: informational
        )
    }

    func testSeparatesDiskReclaimableFromMemoryReleasable() {
        let items = [
            item(category: .caches, action: .deletePath(path: "/tmp/cache", bytes: 1_000), bytes: 1_000),
            item(category: .leftovers, action: .trashLeftover(path: "/tmp/leftover", bytes: 2_000), bytes: 2_000, risk: .caution),
            item(category: .processes, action: .killProcess(pid: 1, name: "App"), bytes: 3_000),
            item(category: .disk, action: .none, bytes: 9_000, informational: true)
        ]

        let metrics = ReviewMetrics.make(visible: items, all: items)

        XCTAssertEqual(metrics.findings, 3)
        XCTAssertEqual(metrics.needReview, 1)
        XCTAssertEqual(metrics.informational, 1)
        XCTAssertEqual(metrics.diskReclaimableBytes, 3_000)
        XCTAssertEqual(metrics.cacheReclaimableBytes, 1_000)
        XCTAssertEqual(metrics.memoryReleasableBytes, 3_000)
    }

    func testCountsAreScopedToVisibleRowsButReclaimableIsGlobal() {
        let cache = item(category: .caches, action: .deletePath(path: "/tmp/cache", bytes: 1_000), bytes: 1_000)
        let process = item(category: .processes, action: .killProcess(pid: 1, name: "App"), bytes: 2_000)
        let info = item(category: .disk, action: .none, bytes: 0, informational: true)

        let metrics = ReviewMetrics.make(visible: [cache], all: [cache, process, info])

        XCTAssertEqual(metrics.findings, 1)
        XCTAssertEqual(metrics.diskReclaimableBytes, 1_000)
        XCTAssertEqual(metrics.memoryReleasableBytes, 2_000)
    }

    func testInformationalAndProtectedItemsAreNotReclaimable() {
        let info = item(category: .disk, action: .deletePath(path: "/tmp/info", bytes: 1_000), bytes: 1_000, informational: true)
        let dangerous = item(category: .processes, action: .killProcess(pid: 1, name: "launchd"), bytes: 2_000, risk: .dangerous)

        let metrics = ReviewMetrics.make(visible: [info, dangerous], all: [info, dangerous])

        XCTAssertEqual(metrics.findings, 1)
        XCTAssertEqual(metrics.diskReclaimableBytes, 0)
        XCTAssertEqual(metrics.memoryReleasableBytes, 0)
    }

    func testAdminOnlyCachesAreNotCountedAsReclaimable() {
        let systemCache = item(
            category: .caches,
            action: .deletePath(path: "/Library/Developer/CoreSimulator/Caches", bytes: 1_000),
            bytes: 1_000,
            risk: .caution
        )

        let metrics = ReviewMetrics.make(visible: [systemCache], all: [systemCache])

        XCTAssertEqual(metrics.findings, 1)
        XCTAssertEqual(metrics.diskReclaimableBytes, 0)
        XCTAssertEqual(metrics.cacheReclaimableBytes, 0)
    }

    func testProtectedProcessesAreNotFindingsOrReviewItems() {
        let protected = ScanItem(
            category: .processes,
            title: "mediaanalysisd",
            detail: "",
            impactLabel: "337 MB",
            impactBytes: 337_000_000,
            risk: .safe,
            action: .none,
            evidence: "ps",
            isInformational: true,
            isProtected: true
        )

        let metrics = ReviewMetrics.make(visible: [protected], all: [protected])

        XCTAssertEqual(metrics.findings, 0)
        XCTAssertEqual(metrics.needReview, 0)
        XCTAssertEqual(metrics.informational, 1)
        XCTAssertEqual(metrics.memoryReleasableBytes, 0)
    }

    func testEmptyInputProducesEmptyMetrics() {
        XCTAssertEqual(ReviewMetrics.make(visible: [], all: []), .empty)
    }
}
