import Foundation
import XCTest
@testable import SiftBar

final class CleanupWhitelistTests: XCTestCase {
    func testAllowsEveryKnownCacheTarget() {
        let home = "/Users/tester"

        for target in CacheCollector.targets(home: home) {
            XCTAssertTrue(
                CleanupWhitelist.allows(target.path, home: home),
                "\(target.path) should be whitelisted"
            )
        }
    }

    func testAllowsTheRootAndItsDescendants() {
        let roots = ["/tmp/siftbar-whitelist/root"]

        XCTAssertTrue(CleanupWhitelist.allows("/tmp/siftbar-whitelist/root", roots: roots))
        XCTAssertTrue(CleanupWhitelist.allows("/tmp/siftbar-whitelist/root/cache", roots: roots))
    }

    func testRejectsPathsOutsideTheRoots() {
        let roots = ["/tmp/siftbar-whitelist/root"]

        XCTAssertFalse(CleanupWhitelist.allows("/tmp/siftbar-whitelist/other", roots: roots))
        XCTAssertFalse(CleanupWhitelist.allows("/tmp", roots: roots))
        XCTAssertFalse(CleanupWhitelist.allows("/", roots: roots))
        XCTAssertFalse(CleanupWhitelist.allows("/System/Library", roots: roots))
    }

    func testRejectsSiblingsSharingTheRootPrefix() {
        let roots = ["/tmp/siftbar-whitelist/root"]

        XCTAssertFalse(CleanupWhitelist.allows("/tmp/siftbar-whitelist/root-evil", roots: roots))
    }

    func testRejectsPathTraversal() {
        let roots = ["/tmp/siftbar-whitelist/root"]

        XCTAssertFalse(CleanupWhitelist.allows("/tmp/siftbar-whitelist/root/../other", roots: roots))
        XCTAssertFalse(CleanupWhitelist.allows("/tmp/siftbar-whitelist/root/../../etc/passwd", roots: roots))
    }

    func testRejectsRelativeAndEmptyPaths() {
        let roots = ["/tmp/siftbar-whitelist/root"]

        XCTAssertFalse(CleanupWhitelist.allows("", roots: roots))
        XCTAssertFalse(CleanupWhitelist.allows("tmp/root", roots: roots))
        XCTAssertFalse(CleanupWhitelist.allows("~/Library/Caches", roots: roots))
    }

    func testRejectsSymlinksThatEscapeTheRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("file.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        addTeardownBlock {
            try? FileManager.default.removeItem(at: base)
        }

        XCTAssertFalse(CleanupWhitelist.allows(
            root.appendingPathComponent("escape/file.txt").path,
            roots: [root.path]
        ))
    }
}
