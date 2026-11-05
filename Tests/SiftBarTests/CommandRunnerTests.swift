import XCTest
@testable import SiftBar

final class CommandRunnerTests: XCTestCase {
    func testCapturesStandardOutputAndExitCode() async throws {
        let result = try await CommandRunner.run(
            "/bin/echo",
            arguments: ["hello", "world"]
        )

        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCapturesStandardErrorAndNonZeroExitCode() async throws {
        let result = try await CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "echo oops >&2; exit 3"]
        )

        XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "oops")
        XCTAssertEqual(result.exitCode, 3)
    }

    func testMissingExecutableThrowsLaunchFailed() async {
        do {
            _ = try await CommandRunner.run("/nonexistent/siftbar-test-binary")
            XCTFail("Expected CommandRunner to throw for a missing executable.")
        } catch let error as CommandError {
            guard case .launchFailed = error else {
                return XCTFail("Expected .launchFailed, got \(error).")
            }
        } catch {
            XCTFail("Expected CommandError, got \(error).")
        }
    }

    func testCommandExceedingTimeoutIsTerminated() async {
        do {
            _ = try await CommandRunner.run(
                "/bin/sleep",
                arguments: ["5"],
                timeout: 0.2
            )
            XCTFail("Expected CommandRunner to time out.")
        } catch let error as CommandError {
            guard case .timedOut = error else {
                return XCTFail("Expected .timedOut, got \(error).")
            }
        } catch {
            XCTFail("Expected CommandError, got \(error).")
        }
    }
}
