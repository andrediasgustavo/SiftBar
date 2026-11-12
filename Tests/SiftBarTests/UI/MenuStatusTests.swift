import Foundation
import XCTest
@testable import SiftBar

final class MenuStatusTests: XCTestCase {
    // MARK: - Status dot

    func testScanningAndApplyingShowAnOrangeDot() {
        XCTAssertEqual(MenuStatus.dot(isScanning: true, isApplying: false, report: nil), "🟠")
        XCTAssertEqual(MenuStatus.dot(isScanning: false, isApplying: true, report: nil), "🟠")
    }

    func testWithoutReportShowsTheNeutralDot() {
        XCTAssertEqual(MenuStatus.dot(isScanning: false, isApplying: false, report: nil), "⚪️")
    }

    func testDotFollowsTheHighestRisk() {
        XCTAssertEqual(dot(risks: [.safe, .caution]), "🟠")
        XCTAssertEqual(dot(risks: [.safe, .caution, .dangerous]), "🔴")
        XCTAssertEqual(dot(risks: [.safe]), "🟢")
    }

    func testInformationalRowsDoNotChangeTheDot() {
        let items = [
            item(risk: .safe),
            item(risk: .dangerous, informational: true)
        ]

        XCTAssertEqual(dot(items: items), "🟢")
    }

    // MARK: - Status text

    func testTextForEveryScanState() {
        XCTAssertEqual(
            MenuStatus.text(isScanning: true, isApplying: false, report: nil),
            "Analyzing…"
        )
        XCTAssertEqual(
            MenuStatus.text(isScanning: false, isApplying: true, report: nil),
            "Applying…"
        )
        XCTAssertEqual(
            MenuStatus.text(isScanning: false, isApplying: false, report: nil),
            "Ready to analyze"
        )
    }

    func testTextCountsOnlyNonInformationalFindings() {
        let report = makeReport(items: [
            item(risk: .safe),
            item(risk: .caution),
            item(risk: .safe),
            item(risk: .dangerous, informational: true)
        ])

        XCTAssertEqual(
            MenuStatus.text(isScanning: false, isApplying: false, report: report),
            "1 need review · 3 findings"
        )
    }

    func testTextReportsAllClearWhenNothingNeedsReview() {
        let report = makeReport(items: [
            item(risk: .safe),
            item(risk: .safe),
            item(risk: .safe, informational: true)
        ])

        XCTAssertEqual(
            MenuStatus.text(isScanning: false, isApplying: false, report: report),
            "All clear · 2 findings"
        )
    }

    func testAnalyzeLabelFollowsTheScanState() {
        XCTAssertEqual(MenuStatus.analyzeLabel(isScanning: true, isApplying: false), "Analyzing…")
        XCTAssertEqual(MenuStatus.analyzeLabel(isScanning: false, isApplying: true), "Applying…")
        XCTAssertEqual(MenuStatus.analyzeLabel(isScanning: false, isApplying: false), "Run Analysis")
    }

    // MARK: - Header rule

    func testHeaderHidesAnalyzeUntilAReportExists() {
        XCTAssertFalse(DashboardPresentation.showsHeaderAnalyze(report: nil))
        XCTAssertTrue(DashboardPresentation.showsHeaderAnalyze(report: makeReport(items: [])))
    }

    // MARK: - Helpers

    private func dot(risks: [Risk]) -> String {
        dot(items: risks.map { item(risk: $0) })
    }

    private func dot(items: [ScanItem]) -> String {
        MenuStatus.dot(
            isScanning: false,
            isApplying: false,
            report: makeReport(items: items)
        )
    }

    private func item(risk: Risk, informational: Bool = false) -> ScanItem {
        ScanItem(
            category: .caches,
            title: "Item",
            detail: "",
            impactLabel: "",
            impactBytes: nil,
            risk: risk,
            action: .none,
            evidence: "",
            isInformational: informational
        )
    }

    private func makeReport(items: [ScanItem]) -> ScanReport {
        ScanReport(
            generatedAt: Date(),
            items: items,
            memory: MemoryStats(
                totalBytes: 8,
                usedBytes: 4,
                swapUsedBytes: 0,
                pressure: .normal
            ),
            disk: DiskStats(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        )
    }
}
