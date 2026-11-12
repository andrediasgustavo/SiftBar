import XCTest
@testable import SiftBar

final class BrewCollectorTests: XCTestCase {
    private let sample = """
    Name              Status  User  File
    postgresql@16     started andre ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist
    redis             stopped andre
    broken            error   andre
    nightly           scheduled - 
    """

    func testParsesOnlyStartedErrorAndScheduledServices() {
        let items = BrewCollector.parse(sample)

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.title), [
            "Homebrew service: postgresql@16",
            "Homebrew service: broken",
            "Homebrew service: nightly"
        ])
    }

    func testMapsStatusToRisk() {
        let items = BrewCollector.parse(sample)

        XCTAssertEqual(items[0].risk, .safe)
        XCTAssertEqual(items[1].risk, .caution)
        XCTAssertEqual(items[2].risk, .safe)
    }

    func testUsesStopServiceAction() {
        let items = BrewCollector.parse(sample)
        let broken = items.first { $0.title.contains("broken") }

        XCTAssertEqual(broken?.action, .stopService(name: "broken"))
        XCTAssertEqual(broken?.impactLabel, "error")
        XCTAssertEqual(broken?.category, .services)
        XCTAssertEqual(broken?.evidence, "brew services list")
    }

    func testIncludesUserWhenPresent() {
        let items = BrewCollector.parse(sample)

        XCTAssertTrue(items[0].detail.contains("User: andre."))
        XCTAssertTrue(items[2].detail.contains("User: -."))
    }

    func testIgnoresHeaderAndStoppedServices() {
        let output = """
        Name   Status  User File
        redis  stopped andre
        """

        XCTAssertTrue(BrewCollector.parse(output).isEmpty)
    }

    func testIgnoresMalformedLines() {
        let output = """
        only-one-column
        good started andre
        """

        let items = BrewCollector.parse(output)

        XCTAssertEqual(items.map(\.title), ["Homebrew service: good"])
    }

    func testEmptyOutputProducesNoItems() {
        XCTAssertTrue(BrewCollector.parse("").isEmpty)
    }
}
