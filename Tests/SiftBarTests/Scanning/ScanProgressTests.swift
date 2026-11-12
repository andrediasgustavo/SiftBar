import Foundation
import XCTest
@testable import SiftBar

final class ScanProgressTests: XCTestCase {
    func testClampsStepAndFraction() {
        let low = ScanProgress(step: 0, fraction: -1, message: "")
        XCTAssertEqual(low.step, 1)
        XCTAssertEqual(low.fraction, 0)

        let high = ScanProgress(step: 9, fraction: 2, message: "")
        XCTAssertEqual(high.step, 4)
        XCTAssertEqual(high.fraction, 1)
    }

    func testStepTitles() {
        XCTAssertEqual(ScanProgress.title(for: 1), "System snapshot")
        XCTAssertEqual(ScanProgress.title(for: 2), "Memory and processes")
        XCTAssertEqual(ScanProgress.title(for: 3), "Caches and leftovers")
        XCTAssertEqual(ScanProgress.title(for: 4), "Disk space map")
        XCTAssertEqual(
            ScanProgress(step: 3, fraction: 0, message: "").stepTitle,
            "Caches and leftovers"
        )
    }

    func testDoneStepsArePreserved() {
        let progress = ScanProgress(step: 3, doneSteps: [1, 2], fraction: 0.5, message: "x")

        XCTAssertTrue(progress.doneSteps.contains(1))
        XCTAssertTrue(progress.doneSteps.contains(2))
        XCTAssertFalse(progress.doneSteps.contains(4))
    }
}
