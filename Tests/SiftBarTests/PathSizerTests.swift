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
