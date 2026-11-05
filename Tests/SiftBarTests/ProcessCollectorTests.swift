import XCTest
@testable import SiftBar

final class ProcessCollectorTests: XCTestCase {
    private let sample = """
      1234 andre    2048000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      5678 root      512000 /usr/libexec/foo
      9999 andre      102400 /usr/bin/small
    not a valid line
      4321 andre     1048576 /Applications/Heavy.app/Contents/MacOS/Heavy
    """

    func testParsesValidProcessLinesAndSkipsMalformedOnes() {
        let entries = ProcessCollector.parse(sample)

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].pid, 1234)
        XCTAssertEqual(entries[0].user, "andre")
        XCTAssertEqual(entries[0].bytes, 2_048_000 * 1024)
        XCTAssertEqual(entries[0].command, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        XCTAssertEqual(entries[0].name, "Google Chrome")
    }

    func testKeepsSpacesInTheCommandPath() {
        let entries = ProcessCollector.parse(
            "42 andre 1000 /Users/a b/My App.app/Contents/MacOS/My App"
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].command, "/Users/a b/My App.app/Contents/MacOS/My App")
        XCTAssertEqual(entries[0].name, "My App")
    }

    func testSkipsLinesWithNonNumericPIDOrRSS() {
        let output = """
        12 andre 1000 /bin/ok
        abc andre 1000 /bin/bad-pid
        13 andre notnum /bin/bad-rss
        14 andre -5 /bin/negative
        """

        let entries = ProcessCollector.parse(output)

        XCTAssertEqual(entries.map(\.command), ["/bin/ok"])
    }

    func testFlagsProcessesAtOneGigabyteAsCaution() {
        XCTAssertEqual(ProcessCollector.risk(for: 0), .safe)
        XCTAssertEqual(ProcessCollector.risk(for: 999_999_999), .safe)
        XCTAssertEqual(ProcessCollector.risk(for: 1_000_000_000), .caution)
        XCTAssertEqual(ProcessCollector.risk(for: 4_000_000_000), .caution)
    }

    func testItemsIncludeOnlyHeavyProcessesSortedByMemory() {
        let items = ProcessCollector.items(from: ProcessCollector.parse(sample))

        // Summary plus Chrome, Heavy, and foo (small is below 150 MB).
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].title, "4 processes running")
        XCTAssertEqual(items[0].risk, .safe)
        XCTAssertEqual(items[0].action, .none)

        XCTAssertEqual(items[1].title, "Google Chrome")
        XCTAssertEqual(items[1].risk, .caution)
        XCTAssertEqual(items[1].impactBytes, 2_048_000 * 1024)

        XCTAssertEqual(items[2].title, "Heavy")
        XCTAssertEqual(items[2].risk, .caution)

        XCTAssertEqual(items[3].title, "foo")
        XCTAssertEqual(items[3].risk, .safe)
    }

    func testItemsUseKillProcessActionWithPID() throws {
        let items = ProcessCollector.items(from: ProcessCollector.parse(sample))
        let chrome = try XCTUnwrap(items.first { $0.title == "Google Chrome" })

        guard case .killProcess(let pid, let name) = chrome.action else {
            return XCTFail("Expected killProcess action, got \(chrome.action).")
        }

        XCTAssertEqual(pid, 1234)
        XCTAssertEqual(name, "Google Chrome")
    }

    func testItemsRespectTheDisplayLimit() {
        let entries = (0..<20).map { index in
            ProcessCollector.Entry(
                pid: Int32(index + 1),
                user: "andre",
                bytes: Int64(200_000_000 + index),
                command: "/bin/proc\(index)"
            )
        }

        let items = ProcessCollector.items(from: entries)

        XCTAssertEqual(items.count, 1 + ProcessCollector.limit)
    }

    func testItemsDoNotDisplayProcessesBelowMinimum() {
        let entries = [
            ProcessCollector.Entry(
                pid: 1,
                user: "andre",
                bytes: ProcessCollector.minimumBytes - 1,
                command: "/bin/small"
            )
        ]

        let items = ProcessCollector.items(from: entries)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "1 processes running")
    }

    func testEmptyInputStillReturnsSummary() {
        let items = ProcessCollector.items(from: [])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "0 processes running")
        XCTAssertEqual(items[0].impactLabel, "0 processes")
    }
}
