import Foundation
import XCTest
@testable import SiftBar

final class HistoryStoreTests: XCTestCase {
    func testAppendAndLoadRoundTrip() throws {
        let store = try makeStore()
        let item = makeItem(impactBytes: 100)
        let report = ActionReport(item: item, success: true, message: "Done.")
        let record = HistoryRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_010),
            entries: [HistoryEntry(item: item, report: report)]
        )

        store.append(record)

        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.id, record.id)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries[0].title, item.title)
        XCTAssertEqual(loaded.entries[0].command, "No action")
        XCTAssertTrue(loaded.entries[0].success)
        XCTAssertEqual(loaded.reclaimedBytes, 100)
        XCTAssertEqual(loaded.succeeded, 1)
        XCTAssertEqual(loaded.failed, 0)
    }

    func testCorruptedFileReturnsEmpty() throws {
        let store = try makeStore()
        try Data("not json".utf8).write(to: store.fileURL)

        XCTAssertTrue(store.load().isEmpty)
    }

    func testKeepsTheMostRecentHundredRecords() throws {
        let store = try makeStore()
        var ids: [UUID] = []

        for index in 0..<105 {
            let id = UUID()
            ids.append(id)

            store.append(HistoryRecord(
                id: id,
                startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                finishedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                entries: []
            ))
        }

        let loaded = store.load()

        XCTAssertEqual(loaded.count, 100)
        XCTAssertEqual(loaded.first?.id, ids[5])
        XCTAssertEqual(loaded.last?.id, ids[104])
    }

    func testFailedEntryDoesNotCountReclaimedBytes() throws {
        let store = try makeStore()
        let item = makeItem(impactBytes: 500)
        let report = ActionReport(item: item, success: false, message: "Permission denied.")
        let record = HistoryRecord(
            id: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            entries: [HistoryEntry(item: item, report: report)]
        )

        store.append(record)

        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.reclaimedBytes, 0)
        XCTAssertEqual(loaded.succeeded, 0)
        XCTAssertEqual(loaded.failed, 1)
    }

    func testHistoryFileIsPrivateToTheUser() throws {
        let store = try makeStore()

        store.append(HistoryRecord(
            id: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            entries: []
        ))

        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    // MARK: - Helpers

    private func makeStore() throws -> HistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        return HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
    }

    private func makeItem(impactBytes: Int64) -> ScanItem {
        ScanItem(
            category: .caches,
            title: "Example cache",
            detail: "Detail",
            impactLabel: "500 MB",
            impactBytes: impactBytes,
            risk: .safe,
            action: .none,
            evidence: "/tmp/example"
        )
    }
}
