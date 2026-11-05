import Foundation
import XCTest
@testable import SiftBar

final class PathSizerTests: XCTestCase {
    func testParsesDUOutputInKilobytes() {
        XCTAssertEqual(PathSizer.parseDU("123\t/Users/tester\n"), 123 * 1024)
        XCTAssertEqual(PathSizer.parseDU("0\t/tmp"), 0)
        XCTAssertEqual(PathSizer.parseDU("2048 /tmp"), 2048 * 1024)
    }

    func testRejectsMalformedDUOutput() {
        XCTAssertNil(PathSizer.parseDU(""))
        XCTAssertNil(PathSizer.parseDU("garbage"))
        XCTAssertNil(PathSizer.parseDU("-5\t/tmp"))
    }

    func testReturnsNilForMissingPath() async {
        let value = await PathSizer.sizeInBytes(of: "/definitely/not/a/real/siftbar/path")

        XCTAssertNil(value)
    }

    func testParsesChildSizesAndSkipsTheRoot() {
        let output = """
        100\t/tmp/root
        50\t/tmp/root/a
        25\t/tmp/root/b c
        """

        let sizes = PathSizer.parseChildSizes(output, root: "/tmp/root")

        XCTAssertEqual(sizes.map(\.path), ["/tmp/root/a", "/tmp/root/b c"])
        XCTAssertEqual(sizes.map(\.bytes), [Int64(50 * 1024), Int64(25 * 1024)])
    }

    func testChildSizeParserIgnoresMalformedLinesAndDuplicates() {
        let output = """
        garbage
        10\t/tmp/root/a
        -1\t/tmp/root/b
        10\t/tmp/root/a
        20\t/tmp/root/c
        """

        let sizes = PathSizer.parseChildSizes(output, root: "/tmp/root")

        XCTAssertEqual(sizes.map(\.path), ["/tmp/root/a", "/tmp/root/c"])
    }

    func testChildSizesForMissingPathIsEmpty() async {
        let sizes = await PathSizer.childSizes(of: "/definitely/not/a/real/siftbar/path")

        XCTAssertTrue(sizes.isEmpty)
    }

    func testChildSizesMeasuresImmediateChildren() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        let child = directory.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1_100_000).write(to: child.appendingPathComponent("payload.bin"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let sizes = await PathSizer.childSizes(of: directory.path)
        let match = sizes.first { $0.path == child.standardizedFileURL.path }

        XCTAssertNotNil(match)
        XCTAssertGreaterThan(match?.bytes ?? 0, 0)
        XCTAssertFalse(sizes.contains { $0.path == directory.standardizedFileURL.path })
    }

    func testMeasuresExistingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let value = await PathSizer.sizeInBytes(of: directory.path)

        XCTAssertNotNil(value)
        XCTAssertGreaterThanOrEqual(value ?? -1, 0)
    }

    func testMeasuresExistingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let file = directory.appendingPathComponent("payload.bin")
        let data = Data(repeating: 0xAB, count: 1_100_000)
        try data.write(to: file)

        let value = await PathSizer.sizeInBytes(of: file.path)

        XCTAssertNotNil(value)
        XCTAssertGreaterThan(value ?? 0, 0)
    }
}
