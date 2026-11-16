import Foundation
import XCTest
@testable import SiftBar

final class ReportExporterTests: XCTestCase {
    private var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func report(items: [ScanItem]) -> ScanReport {
        ScanReport(
            generatedAt: Date(),
            items: items,
            memory: MemoryStats(
                totalBytes: 16_000_000_000,
                usedBytes: 8_000_000_000,
                swapUsedBytes: 0,
                pressure: .normal,
                appBytes: 4_000_000_000,
                wiredBytes: 2_000_000_000,
                compressedBytes: 1_000_000_000,
                cachedBytes: 1_000_000_000,
                freeBytes: 8_000_000_000
            ),
            disk: DiskStats(
                totalBytes: 500_000_000_000,
                usedBytes: 250_000_000_000,
                freeBytes: 250_000_000_000
            )
        )
    }

    private var cacheItem: ScanItem {
        ScanItem(
            category: .caches,
            title: "npm cache",
            detail: "Recreatable cache data.",
            impactLabel: "120 MB",
            impactBytes: 120_000_000,
            risk: .safe,
            action: .deletePath(path: "\(home)/.npm", bytes: 120_000_000),
            evidence: "\(home)/.npm"
        )
    }

    private var leftoverItem: ScanItem {
        ScanItem(
            category: .leftovers,
            title: "Possible leftover: JetBrains",
            detail: "A receipt uses the vendor identifier “jetbrains”.",
            impactLabel: "1.2 GB",
            impactBytes: 1_200_000_000,
            risk: .caution,
            action: .trashLeftover(path: "\(home)/Library/Application Support/JetBrains", bytes: 1_200_000_000),
            evidence: "\(home)/Library/Application Support/JetBrains",
            warning: "Low confidence: an installed app or receipt is related to this folder.",
            isInformational: true,
            leftoverConfidence: .low
        )
    }

    func testHeaderSummaryAndSections() {
        let markdown = ReportExporter.markdown(
            for: report(items: [cacheItem]),
            version: "0.7.0 (10)",
            includesProtectedFolders: true
        )

        XCTAssertTrue(markdown.hasPrefix("# SiftBar report"))
        XCTAssertTrue(markdown.contains("- SiftBar: 0.7.0 (10)"))
        XCTAssertTrue(markdown.contains("- Personal folders (Desktop, Documents, Downloads): measured"))
        XCTAssertTrue(markdown.contains("- Findings: 1 (0 need review)"))
        XCTAssertTrue(markdown.contains("## Findings"))
        XCTAssertTrue(markdown.contains("### Caches"))
        XCTAssertTrue(markdown.contains("npm cache"))
        XCTAssertTrue(markdown.contains("Command:"))
        XCTAssertTrue(markdown.contains("## Notes"))
    }

    func testSkipsPersonalFoldersWhenAccessIsPartial() {
        let markdown = ReportExporter.markdown(
            for: report(items: []),
            version: "dev",
            includesProtectedFolders: false
        )

        XCTAssertTrue(markdown.contains("Personal folders (Desktop, Documents, Downloads): skipped"))
        XCTAssertTrue(markdown.contains("No findings."))
    }

    func testAbbreviatesHomePaths() {
        let markdown = ReportExporter.markdown(
            for: report(items: [cacheItem]),
            includesProtectedFolders: true
        )

        XCTAssertTrue(markdown.contains("`~/.npm`"))
        XCTAssertFalse(markdown.contains(home + "/.npm"))
    }

    func testLowConfidenceLeftoversAreNotGivenACommand() {
        let markdown = ReportExporter.markdown(
            for: report(items: [leftoverItem]),
            includesProtectedFolders: true
        )

        XCTAssertTrue(markdown.contains("Confidence: Low confidence"))
        XCTAssertTrue(markdown.contains("Locked: review it in Finder first."))
        XCTAssertFalse(markdown.contains("Move leftover app data to Trash"))
    }

    func testInformationalContextIsSeparateFromFindings() {
        let info = ScanItem(
            category: .disk,
            title: "Startup disk",
            detail: "Disk usage is healthy.",
            impactLabel: "50%",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: "df -k",
            isInformational: true
        )

        let markdown = ReportExporter.markdown(
            for: report(items: [info]),
            includesProtectedFolders: true
        )

        XCTAssertTrue(markdown.contains("## Read-only context"))
        XCTAssertTrue(markdown.contains("[Info] Startup disk"))
        XCTAssertFalse(markdown.contains("[Safe] Startup disk"))
        XCTAssertTrue(markdown.contains("No findings."))
    }

    func testDiskMapIncludesReadOnlyChildren() {
        let child = ScanItem(
            category: .disk,
            title: "Trash",
            detail: "Deleted files.",
            impactLabel: "2 GB",
            impactBytes: 2_000_000_000,
            risk: .safe,
            action: .none,
            evidence: "du -sk ~/.Trash",
            isInformational: true,
            isBreakdown: true
        )
        let parent = ScanItem(
            category: .disk,
            title: "System & other",
            detail: "Remainder.",
            impactLabel: "20 GB",
            impactBytes: 20_000_000_000,
            risk: .safe,
            action: .none,
            evidence: "total used - measured categories",
            isInformational: true,
            isBreakdown: true,
            children: [child]
        )

        let markdown = ReportExporter.markdown(
            for: report(items: [parent]),
            includesProtectedFolders: true
        )

        XCTAssertTrue(markdown.contains("## Disk map"))
        XCTAssertTrue(markdown.contains("- **System & other** — 20 GB"))
        XCTAssertTrue(markdown.contains("  - Trash — 2 GB"))
    }

    func testWarningsAreListedOnce() {
        let markdown = ReportExporter.markdown(
            for: report(items: [leftoverItem]),
            includesProtectedFolders: true
        )

        XCTAssertTrue(markdown.contains("## Warnings"))
        XCTAssertTrue(markdown.contains("Low confidence"))
    }

    func testSuggestedFilenameIsStable() {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 15
        let date = Calendar(identifier: .gregorian).date(from: components)!

        XCTAssertEqual(
            ReportExporter.suggestedFilename(for: date),
            "SiftBar-Report-2026-11-15.md"
        )
    }

    func testRedactHandlesHomeExactly() {
        XCTAssertEqual(ReportExporter.redact(home, home: home), "~")
        XCTAssertEqual(ReportExporter.redact("\(home)/Library/Caches", home: home), "~/Library/Caches")
        XCTAssertEqual(ReportExporter.redact("/Applications/Foo.app", home: home), "/Applications/Foo.app")
    }
}
