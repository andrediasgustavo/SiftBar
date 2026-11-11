import Foundation
import XCTest
@testable import SiftBar

final class SizeCacheTests: XCTestCase {
    func testStoreAndLookupRoundTrip() throws {
        let cache = try makeCache()
        let signature = Date(timeIntervalSince1970: 100)

        cache.store(path: "/Users/tester/Library/Caches", bytes: 42, signature: signature)

        XCTAssertEqual(
            cache.lookup(path: "/Users/tester/Library/Caches", signature: signature),
            42
        )
    }

    func testLookupMissesWhenTheSignatureChanges() throws {
        let cache = try makeCache()

        cache.store(
            path: "/Users/tester/Library/Caches",
            bytes: 42,
            signature: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(cache.lookup(
            path: "/Users/tester/Library/Caches",
            signature: Date(timeIntervalSince1970: 200)
        ))
    }

    func testLookupMissesWhenTheEntryExpired() throws {
        let cache = try makeCache(ttl: 60)
        let signature = Date(timeIntervalSince1970: 100)
        let recordedAt = Date(timeIntervalSince1970: 1_000)

        cache.store(
            path: "/Users/tester/Library/Caches",
            bytes: 42,
            signature: signature,
            now: recordedAt
        )

        XCTAssertEqual(
            cache.lookup(
                path: "/Users/tester/Library/Caches",
                signature: signature,
                now: recordedAt.addingTimeInterval(59)
            ),
            42
        )
        XCTAssertNil(cache.lookup(
            path: "/Users/tester/Library/Caches",
            signature: signature,
            now: recordedAt.addingTimeInterval(61)
        ))
    }

    func testInvalidateDropsThePathAndItsDescendants() throws {
        let cache = try makeCache()
        let signature = Date(timeIntervalSince1970: 100)

        cache.store(path: "/Users/tester/Library/Caches", bytes: 1, signature: signature)
        cache.store(path: "/Users/tester/Library/Caches/App", bytes: 2, signature: signature)
        cache.store(path: "/Users/tester/Library/Developer", bytes: 3, signature: signature)

        cache.invalidate(path: "/Users/tester/Library/Caches")

        XCTAssertNil(cache.lookup(path: "/Users/tester/Library/Caches", signature: signature))
        XCTAssertNil(cache.lookup(path: "/Users/tester/Library/Caches/App", signature: signature))
        XCTAssertEqual(
            cache.lookup(path: "/Users/tester/Library/Developer", signature: signature),
            3
        )
    }

    func testDisabledCacheNeverStores() {
        let signature = Date()

        SizeCache.disabled.store(path: "/Users/tester/Library/Caches", bytes: 1, signature: signature)

        XCTAssertNil(SizeCache.disabled.lookup(path: "/Users/tester/Library/Caches", signature: signature))
    }

    func testTemporaryPathsAreNotCached() throws {
        let cache = try makeCache()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarSizeCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let signature = Date()
        cache.store(path: directory.path, bytes: 10, signature: signature)

        XCTAssertNil(cache.lookup(path: directory.path, signature: signature))
    }

    func testEntriesSurviveReloadFromDisk() throws {
        let url = try makeCacheURL()
        let signature = Date(timeIntervalSince1970: 500)

        SizeCache(fileURL: url).store(
            path: "/Users/tester/Library/Caches",
            bytes: 7,
            signature: signature
        )

        let reloaded = SizeCache(fileURL: url)

        XCTAssertEqual(
            reloaded.lookup(path: "/Users/tester/Library/Caches", signature: signature),
            7
        )
    }

    func testCacheFileIsPrivateToTheUser() throws {
        let url = try makeCacheURL()
        let cache = SizeCache(fileURL: url)

        cache.store(
            path: "/Users/tester/Library/Caches",
            bytes: 7,
            signature: Date(timeIntervalSince1970: 500)
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    // MARK: - Helpers

    private func makeCache(ttl: TimeInterval = 600) throws -> SizeCache {
        SizeCache(fileURL: try makeCacheURL(), ttl: ttl)
    }

    private func makeCacheURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarSizeCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("sizecache.json")
    }
}
