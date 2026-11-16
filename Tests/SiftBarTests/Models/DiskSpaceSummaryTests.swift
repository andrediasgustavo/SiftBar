import XCTest
@testable import SiftBar

final class DiskSpaceSummaryTests: XCTestCase {
    private func breakdown(_ title: String, _ bytes: Int64) -> ScanItem {
        ScanItem(
            category: .disk,
            title: title,
            detail: "",
            impactLabel: "\(bytes)",
            impactBytes: bytes,
            risk: .safe,
            action: .none,
            evidence: "du -sk /tmp",
            isInformational: true,
            isBreakdown: true
        )
    }

    private func items() -> [ScanItem] {
        [
            breakdown("Applications", 10),
            breakdown("Developer", 20),
            breakdown("Documents & media", 5),
            breakdown("iCloud Drive", 1),
            breakdown("App data", 30),
            breakdown("Caches", 40),
            breakdown("System-wide data", 50),
            breakdown("System & other", 60)
        ]
    }

    private func disk(used: Int64 = 216) -> DiskStats {
        DiskStats(totalBytes: 500, usedBytes: used, freeBytes: 500 - used)
    }

    func testGroupsTechnicalCategoriesIntoFourPlainGroups() {
        let summary = DiskSpaceSummary.make(
            items: items(),
            disk: disk(),
            includesProtectedFolders: true
        )

        XCTAssertEqual(summary.groups.map(\.kind), [.apps, .files, .appData, .system])
        XCTAssertEqual(summary.groups.map(\.title), [
            "Apps and tools",
            "Your files",
            "App data and caches",
            "macOS and protected"
        ])
        XCTAssertEqual(summary.groups.map(\.bytes), [30, 6, 70, 110])
        XCTAssertEqual(summary.groups.reduce(0) { $0 + $1.bytes }, 216)
        XCTAssertEqual(summary.usedBytes, 216)
    }

    func testPartsUseFriendlyNames() {
        let summary = DiskSpaceSummary.make(
            items: items(),
            disk: disk(),
            includesProtectedFolders: true
        )

        let names = summary.groups.flatMap { $0.parts.map(\.title) }
        XCTAssertTrue(names.contains("Developer tools"))
        XCTAssertTrue(names.contains("Documents, Desktop and Downloads"))
        XCTAssertTrue(names.contains("System files"))
        XCTAssertTrue(names.contains("macOS and protected files"))
        XCTAssertFalse(names.contains("System & other"))
    }

    func testPartialAccessKeepsYourFilesVisibleButUnmeasured() {
        let summary = DiskSpaceSummary.make(
            items: items().filter { $0.title != "Documents & media" && $0.title != "iCloud Drive" },
            disk: disk(),
            includesProtectedFolders: false
        )

        let files = summary.groups.first { $0.kind == .files }
        XCTAssertNotNil(files)
        XCTAssertEqual(files?.isMeasured, false)
        XCTAssertEqual(files?.bytes, 0)
        XCTAssertTrue(summary.groups.filter(\.isMeasured).allSatisfy { $0.bytes > 0 })
    }

    func testSmallGapIsKeptInsideTheSystemGroup() {
        let summary = DiskSpaceSummary.make(
            items: [breakdown("Applications", 10)],
            disk: disk(used: 15),
            includesProtectedFolders: false
        )

        let system = summary.groups.first { $0.kind == .system }
        XCTAssertEqual(system?.bytes, 5)
        XCTAssertEqual(system?.parts.first?.title, "Other system data")
        XCTAssertEqual(summary.usedBytes, 15)
    }

    func testEmptyReportProducesNoGroups() {
        let summary = DiskSpaceSummary.make(
            items: [],
            disk: DiskStats(totalBytes: 0, usedBytes: 0, freeBytes: 0),
            includesProtectedFolders: true
        )

        XCTAssertTrue(summary.groups.isEmpty)
        XCTAssertEqual(summary.usedBytes, 0)
    }

    func testKnownTechnicalTitlesMapToAGroup() {
        XCTAssertEqual(DiskSpaceSummary.kind(for: "Applications"), .apps)
        XCTAssertEqual(DiskSpaceSummary.kind(for: "Developer"), .apps)
        XCTAssertEqual(DiskSpaceSummary.kind(for: "Caches"), .appData)
        XCTAssertEqual(DiskSpaceSummary.kind(for: "System & other"), .system)
        XCTAssertNil(DiskSpaceSummary.kind(for: "Startup disk"))
    }
}
