import XCTest
@testable import SiftBar

final class SystemProbeTests: XCTestCase {
    func testParsesAvailableDiskSpaceFromDFOutput() throws {
        let output = """
        Filesystem      1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s1s1   971350180  12345678 123456789    10%   /
        """

        let bytes = try SystemProbe.parseFreeDisk(from: output)

        XCTAssertEqual(bytes, 123_456_789 * 1024)
    }

    func testParsesSingleLineOutputWithoutHeaderAsError() {
        XCTAssertThrowsError(try SystemProbe.parseFreeDisk(from: "garbage"))
    }

    func testRejectsNonNumericAvailableBlocks() {
        let output = """
        Filesystem      1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s1s1   971350180  12345678    unknown    10%   /
        """

        XCTAssertThrowsError(try SystemProbe.parseFreeDisk(from: output))
    }

    func testSnapshotReturnsRealSystemValues() async throws {
        let snapshot = try await SystemProbe.snapshot()

        XCTAssertGreaterThan(snapshot.totalMemoryBytes, 0)
        XCTAssertGreaterThan(snapshot.freeDiskBytes, 0)
    }
}
