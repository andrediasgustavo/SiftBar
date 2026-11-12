import XCTest
@testable import SiftBar

final class ReviewFilterTests: XCTestCase {
    private func item(
        _ category: ItemCategory = .caches,
        _ risk: Risk = .safe,
        title: String,
        detail: String = "",
        impactLabel: String = "",
        evidence: String = ""
    ) -> ScanItem {
        ScanItem(
            category: category,
            title: title,
            detail: detail,
            impactLabel: impactLabel,
            impactBytes: nil,
            risk: risk,
            action: .none,
            evidence: evidence
        )
    }

    private var sample: [ScanItem] {
        [
            item(.processes, .caution, title: "Google Chrome", detail: "39 processes", impactLabel: "1.7 GB", evidence: "/Applications/Google Chrome.app"),
            item(.caches, .safe, title: "npm cache", detail: "Recreatable cache", impactLabel: "120 MB", evidence: "du -sk /Users/me/.npm"),
            item(.startup, .caution, title: "Launch item: com.example.agent", detail: "Registered in /Library/LaunchAgents", evidence: "/Library/LaunchAgents"),
            item(.memory, .dangerous, title: "Memory pressure", detail: "System is under memory pressure", impactLabel: "Critical", evidence: "memory_pressure")
        ]
    }

    func testEmptyFilterReturnsEverythingInOrder() {
        let filter = ReviewFilter()

        let result = filter.apply(to: sample)

        XCTAssertEqual(result.count, sample.count)
        XCTAssertEqual(result.map(\.title), sample.map(\.title))
        XCTAssertFalse(filter.isActive)
    }

    func testCategoryFilter() {
        var filter = ReviewFilter()
        filter.category = .processes

        let result = filter.apply(to: sample)

        XCTAssertEqual(result.map(\.title), ["Google Chrome"])
        XCTAssertTrue(filter.isActive)
    }

    func testRiskFilter() {
        var filter = ReviewFilter()
        filter.risk = .caution

        let result = filter.apply(to: sample)

        XCTAssertEqual(result.map(\.title), [
            "Google Chrome",
            "Launch item: com.example.agent"
        ])
    }

    func testCategoryAndRiskFiltersCombine() {
        var filter = ReviewFilter()
        filter.category = .startup
        filter.risk = .safe

        XCTAssertTrue(filter.apply(to: sample).isEmpty)

        filter.risk = .caution
        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["Launch item: com.example.agent"])
    }

    func testSearchMatchesTitleCaseInsensitively() {
        var filter = ReviewFilter()
        filter.searchText = "CHROME"

        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["Google Chrome"])
    }

    func testSearchMatchesDetail() {
        var filter = ReviewFilter()
        filter.searchText = "recreatable"

        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["npm cache"])
    }

    func testSearchMatchesEvidence() {
        var filter = ReviewFilter()
        filter.searchText = "LaunchAgents"

        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["Launch item: com.example.agent"])
    }

    func testSearchMatchesCategoryName() {
        var filter = ReviewFilter()
        filter.searchText = "memory"

        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["Memory pressure"])
    }

    func testSearchRequiresEveryTerm() {
        var filter = ReviewFilter()
        filter.searchText = "chrome applications"

        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["Google Chrome"])

        filter.searchText = "chrome memory"
        XCTAssertTrue(filter.apply(to: sample).isEmpty)
    }

    func testSearchIgnoresDiacritics() {
        let items = [item(.leftovers, .caution, title: "Café leftover")]

        var filter = ReviewFilter()
        filter.searchText = "cafe"

        XCTAssertEqual(filter.apply(to: items).count, 1)
    }

    func testWhitespaceOnlySearchIsNotActive() {
        var filter = ReviewFilter()
        filter.searchText = "   "

        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: sample).count, sample.count)
    }

    func testSearchTrimsOuterWhitespace() {
        var filter = ReviewFilter()
        filter.searchText = "  npm  "

        XCTAssertEqual(filter.apply(to: sample).map(\.title), ["npm cache"])
    }

    func testNoMatchesReturnsEmpty() {
        var filter = ReviewFilter()
        filter.searchText = "definitely-not-present"

        XCTAssertTrue(filter.apply(to: sample).isEmpty)
    }

    func testResetClearsEverything() {
        var filter = ReviewFilter()
        filter.category = .caches
        filter.risk = .safe
        filter.searchText = "npm"

        filter.reset()

        XCTAssertEqual(filter, ReviewFilter())
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: sample).count, sample.count)
    }

    func testCountsByCategoryAndRisk() {
        XCTAssertEqual(ReviewFilter.count(of: .processes, in: sample), 1)
        XCTAssertEqual(ReviewFilter.count(of: .caches, in: sample), 1)
        XCTAssertEqual(ReviewFilter.count(of: .caution, in: sample), 2)
        XCTAssertEqual(ReviewFilter.count(of: .dangerous, in: sample), 1)
        XCTAssertEqual(ReviewFilter.count(of: .safe, in: sample), 1)
    }

    func testFilterPreservesOriginalOrder() {
        var filter = ReviewFilter()
        filter.risk = .caution

        let result = filter.apply(to: sample)

        XCTAssertEqual(result.map(\.title), [
            "Google Chrome",
            "Launch item: com.example.agent"
        ])
    }
}
