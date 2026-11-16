import XCTest
@testable import SiftBar

final class ReviewOrderingTests: XCTestCase {
    private func item(
        _ title: String,
        risk: Risk,
        bytes: Int64? = nil,
        informational: Bool = false,
        protected: Bool = false,
        confidence: LeftoverConfidence? = nil
    ) -> ScanItem {
        ScanItem(
            category: .caches,
            title: title,
            detail: "",
            impactLabel: "",
            impactBytes: bytes,
            risk: risk,
            action: .none,
            evidence: "",
            isInformational: informational,
            isProtected: protected,
            leftoverConfidence: confidence
        )
    }

    func testInformationalRowsComeAfterEverySafeRow() {
        let items = [
            item("Info caution", risk: .caution, bytes: 5_000, informational: true),
            item("Safe", risk: .safe, bytes: 1_000),
            item("Caution", risk: .caution, bytes: 2_000),
            item("Info safe", risk: .safe, bytes: 4_000, informational: true),
            item("Dangerous", risk: .dangerous, bytes: 3_000)
        ]

        XCTAssertEqual(ReviewOrdering.sorted(items).map(\.title), [
            "Dangerous",
            "Caution",
            "Safe",
            "Info caution",
            "Info safe"
        ])
    }

    func testProtectedRowsStayAfterOtherInformationalRows() {
        let items = [
            item("Info", risk: .safe, bytes: 1_000, informational: true),
            item("Protected", risk: .safe, bytes: 2_000, informational: true, protected: true)
        ]

        XCTAssertEqual(ReviewOrdering.sorted(items).map(\.title), ["Info", "Protected"])
    }

    func testLowConfidenceLeftoversSortAfterHighWithinTheSameRisk() {
        let items = [
            item("Low", risk: .caution, bytes: 9_000, confidence: .low),
            item("High", risk: .caution, bytes: 1_000, confidence: .high),
            item("Medium", risk: .caution, bytes: 5_000, confidence: .medium)
        ]

        XCTAssertEqual(ReviewOrdering.sorted(items).map(\.title), ["High", "Medium", "Low"])
    }

    func testImpactThenTitleBreakTies() {
        let items = [
            item("Beta", risk: .safe, bytes: 1_000),
            item("Alpha", risk: .safe, bytes: 1_000),
            item("Bigger", risk: .safe, bytes: 2_000)
        ]

        XCTAssertEqual(ReviewOrdering.sorted(items).map(\.title), ["Bigger", "Alpha", "Beta"])
    }
}
