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

    // MARK: - Leftovers

    func testAllowsTopLevelApplicationSupportFolder() throws {
        let home = try makeHome()
        let folder = home
            .appendingPathComponent("Library/Application Support/LeftoverApp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertTrue(CleanupWhitelist.allowsLeftover(folder.path, home: home.path))
    }

    func testRejectsNestedApplicationSupportFolder() throws {
        let home = try makeHome()
        let folder = home
            .appendingPathComponent("Library/Application Support/LeftoverApp/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertFalse(CleanupWhitelist.allowsLeftover(folder.path, home: home.path))
    }

    func testRejectsHiddenAndAppleFolders() throws {
        let home = try makeHome()
        let hidden = home.appendingPathComponent("Library/Application Support/.hidden", isDirectory: true)
        let apple = home.appendingPathComponent("Library/Application Support/com.apple.foo", isDirectory: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apple, withIntermediateDirectories: true)

        XCTAssertFalse(CleanupWhitelist.allowsLeftover(hidden.path, home: home.path))
        XCTAssertFalse(CleanupWhitelist.allowsLeftover(apple.path, home: home.path))
    }

    func testRejectsPathsOutsideApplicationSupport() throws {
        let home = try makeHome()
        let outside = home.appendingPathComponent("Documents/Important", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        XCTAssertFalse(CleanupWhitelist.allowsLeftover(outside.path, home: home.path))
        XCTAssertFalse(CleanupWhitelist.allowsLeftover("/Library/Application Support/Foo", home: home.path))
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: home)
        }
        return home
    }
}
