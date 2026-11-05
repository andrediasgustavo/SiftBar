import Foundation
import XCTest
@testable import SiftBar

final class ReviewActionModelTests: XCTestCase {
    @MainActor
    func testSelectAllOnlySelectsChangeableItems() async {
        let model = ReviewActionModel()
        let safe = item(action: .killProcess(pid: 1, name: "Safe"), risk: .safe)
        let dangerous = item(action: .killProcess(pid: 2, name: "Danger"), risk: .dangerous)
        let readOnly = item(action: .none)
        let admin = item(action: .disableLaunchItem(label: "x"), evidence: "/Library/LaunchDaemons")

        model.selectAll([safe, dangerous, readOnly, admin])

        XCTAssertTrue(model.isSelected(safe))
        XCTAssertFalse(model.isSelected(dangerous))
        XCTAssertFalse(model.isSelected(readOnly))
        XCTAssertFalse(model.isSelected(admin))
    }

    @MainActor
    func testSelectNeedingReviewSkipsSafeItems() async {
        let model = ReviewActionModel()
        let safe = item(action: .killProcess(pid: 1, name: "Safe"), risk: .safe)
        let caution = item(action: .killProcess(pid: 2, name: "Caution"), risk: .caution)
        let dangerous = item(action: .killProcess(pid: 3, name: "Danger"), risk: .dangerous)

        model.selectNeedingReview([safe, caution, dangerous])

        XCTAssertFalse(model.isSelected(safe))
        XCTAssertTrue(model.isSelected(caution))
        XCTAssertFalse(model.isSelected(dangerous))
    }

    @MainActor
    func testSelectedItemsPreserveInputOrder() async {
        let model = ReviewActionModel()
        let first = item(action: .killProcess(pid: 1, name: "First"))
        let second = item(action: .killProcess(pid: 2, name: "Second"))

        model.selectAll([second, first])

        XCTAssertEqual(
            model.selectedItems(in: [first, second]).map(\.title),
            [first.title, second.title]
        )
    }

    @MainActor
    func testClearRemovesSelection() async {
        let model = ReviewActionModel()
        let item = item(action: .killProcess(pid: 1, name: "Safe"))

        model.toggle(item)
        XCTAssertTrue(model.isSelected(item))

        model.clear()
        XCTAssertFalse(model.isSelected(item))
    }

    @MainActor
    func testToggleIgnoresUnchangeableItems() async {
        let model = ReviewActionModel()
        let readOnly = item(action: .none)

        model.toggle(readOnly)

        XCTAssertFalse(model.isSelected(readOnly))
    }

    @MainActor
    func testBeginAndCancelConfirmation() async {
        let model = ReviewActionModel()
        let item = item(action: .killProcess(pid: 1, name: "Safe"))

        model.beginConfirmation(with: [item])

        XCTAssertTrue(model.isConfirming)
        XCTAssertEqual(model.pending.map(\.id), [item.id])

        model.cancelConfirmation()

        XCTAssertFalse(model.isConfirming)
        XCTAssertTrue(model.pending.isEmpty)
    }

    // MARK: - Helpers

    private func item(
        action: ItemAction,
        risk: Risk = .safe,
        evidence: String = "/tmp/example"
    ) -> ScanItem {
        ScanItem(
            category: .startup,
            title: "Item \(action)",
            detail: "Detail",
            impactLabel: "1 MB",
            impactBytes: nil,
            risk: risk,
            action: action,
            evidence: evidence
        )
    }
}
