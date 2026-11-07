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

    func testChildSizeParserIgnoresDeeperDescendants() {
        let output = """
        10\t/tmp/root/a/nested
        20\t/tmp/root/a
        30\t/tmp/root/b
        """

        let sizes = PathSizer.parseChildSizes(output, root: "/tmp/root")

        XCTAssertEqual(sizes.map(\.path), ["/tmp/root/a", "/tmp/root/b"])
    }

    func testChildSizesForMissingPathIsEmpty() async {
        let sizes = await PathSizer.childSizes(of: "/definitely/not/a/real/siftbar/path")

        XCTAssertTrue(sizes.isEmpty)
    }

    func testChildSizesFiltersFilesBelowTheThreshold() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let large = directory.appendingPathComponent("large.bin")
        let small = directory.appendingPathComponent("small.bin")
        try Data(repeating: 0xAB, count: 2_000_000).write(to: large)
        try Data(repeating: 0xCD, count: 1_000).write(to: small)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let sizes = await PathSizer.childSizes(of: directory.path, minimumFileBytes: 1_000_000)
        let paths = Set(sizes.map(\.path))

        XCTAssertTrue(paths.contains(large.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(small.standardizedFileURL.path))
    }

    func testChildSizesMeasuresImmediateChildren() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        let child = directory.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1_100_000).write(to: child.appendingPathComponent("payload.bin"))

        // A large file directly under the root must appear too; `du -d 1`
        // alone would silently omit files.
        let directFile = directory.appendingPathComponent("direct.bin")
        try Data(repeating: 0xCD, count: 1_100_000).write(to: directFile)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let sizes = await PathSizer.childSizes(of: directory.path)

        XCTAssertNotNil(sizes.first { $0.path == child.standardizedFileURL.path })
        XCTAssertNotNil(sizes.first { $0.path == directFile.standardizedFileURL.path })
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

    func testSizesOfChildrenCanExcludeSensitiveFolders() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        for (name, size) in [("Kept", 1_000_000), ("Photos", 2_000_000), (".hidden", 1_000_000)] {
            let child = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: size).write(to: child.appendingPathComponent("payload.bin"))
        }

        let all = await PathSizer.sizesOfChildren(of: directory.path)
        let filtered = await PathSizer.sizesOfChildren(
            of: directory.path,
            excludingNames: ["photos"]
        )

        XCTAssertGreaterThan(all, filtered)
        XCTAssertGreaterThanOrEqual(filtered, 1_000_000)
    }
}
