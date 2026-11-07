import Foundation
import XCTest
@testable import SiftBar

final class FullDiskAccessTests: XCTestCase {
    func testReadableProbeMeansGranted() throws {
        let file = try makeFile()

        let status = FullDiskAccess.status(probes: [.init(path: file.path)])

        XCTAssertEqual(status, .granted)
    }

    func testUnreadableProbeMeansDenied() throws {
        let file = try makeFile()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: file.path
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.path
            )
        }

        let status = FullDiskAccess.status(probes: [.init(path: file.path)])

        XCTAssertEqual(status, .denied)
    }

    func testMissingProbesMeanUnknown() {
        let status = FullDiskAccess.status(probes: [
            .init(path: "/definitely/not/a/real/siftbar/probe")
        ])

        XCTAssertEqual(status, .unknown)
    }

    func testReadableProbeWinsOverMissingOne() throws {
        let file = try makeFile()

        let status = FullDiskAccess.status(probes: [
            .init(path: "/definitely/not/a/real/siftbar/probe"),
            .init(path: file.path)
        ])

        XCTAssertEqual(status, .granted)
    }

    func testUnreadableDirectoryProbeMeansDenied() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: directory.path
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }

        let status = FullDiskAccess.status(probes: [
            .init(path: directory.path, isDirectory: true)
        ])

        XCTAssertEqual(status, .denied)
    }

    private func makeFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("probe.db")
        try Data("probe".utf8).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return file
    }
}
