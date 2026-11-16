import XCTest
@testable import SiftBar

final class ActionResultSummaryTests: XCTestCase {
    private func make(
        changed: Int = 1,
        failed: Int = 0,
        reports: Int = 1,
        freed: Int64 = 0,
        moved: Int64 = 0,
        memory: Int64 = 0
    ) -> ActionResultSummary {
        ActionResultSummary.make(
            changedCount: changed,
            failedCount: failed,
            reportCount: reports,
            freedBytes: freed,
            movedBytes: moved,
            memoryBytes: memory,
            formatDisk: { "\($0) B" },
            formatMemory: { "\($0) B" }
        )
    }

    func testFreedOnlyDoesNotAskToEmptyTheTrash() {
        let summary = make(freed: 1_000)

        XCTAssertEqual(summary.headline, "1000 B freed")
        XCTAssertEqual(summary.detail, "1 succeeded · 0 failed · Space freed immediately")
        XCTAssertFalse(summary.showsTrashButton)
    }

    func testMovedOnlyPointsToTheTrash() {
        let summary = make(moved: 2_000)

        XCTAssertEqual(summary.headline, "2000 B moved to Trash")
        XCTAssertEqual(summary.detail, "1 succeeded · 0 failed · Empty the Trash to free space")
        XCTAssertTrue(summary.showsTrashButton)
    }

    func testFreedMovedAndMemoryAreAllReported() {
        let summary = make(freed: 1_000, moved: 2_000, memory: 3_000)

        XCTAssertEqual(summary.headline, "1000 B freed · 2000 B moved to Trash · 3000 B RAM released")
        XCTAssertTrue(summary.showsTrashButton)
    }

    func testFailureWithPartialSuccessUsesThePartialHeadline() {
        let summary = make(changed: 2, failed: 1, reports: 3, moved: 5_000)

        XCTAssertEqual(summary.headline, "2 of 3 succeeded")
        XCTAssertTrue(summary.detail.contains("Empty the Trash"))
        XCTAssertTrue(summary.showsTrashButton)
    }

    func testAllFailed() {
        let summary = make(changed: 0, failed: 3, reports: 3)

        XCTAssertEqual(summary.headline, "3 items failed")
        XCTAssertEqual(summary.detail, "0 succeeded · 3 failed")
        XCTAssertFalse(summary.showsTrashButton)
    }

    func testChangedWithoutBytesIsTheFallback() {
        let summary = make(changed: 2, reports: 2)

        XCTAssertEqual(summary.headline, "2 items changed")
        XCTAssertEqual(summary.detail, "2 succeeded · 0 failed")
    }

    func testSingularFailure() {
        XCTAssertEqual(make(changed: 0, failed: 1, reports: 1).headline, "1 item failed")
    }
}
