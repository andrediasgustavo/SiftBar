import Foundation
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

    func testArgumentsAreNotInterpretedByShell() async throws {
        let marker = "/tmp/siftbar-\(UUID().uuidString)"
        let result = try await CommandRunner.run(
            "/bin/echo",
            arguments: ["$(whoami)", "; rm -rf \(marker)", "a && b"]
        )

        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "$(whoami) ; rm -rf \(marker) a && b"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func testEmptyArgumentsArePreserved() async throws {
        let result = try await CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "printf '<%s>' \"$@\"", "sh", "", "x"]
        )

        XCTAssertEqual(result.stdout, "<><x>")
    }

    func testDrainsOutputLargerThanThePipeBuffer() async throws {
        let result = try await CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 5000 ]; do echo 0123456789012345678901234567890123456789; i=$((i+1)); done"]
        )

        XCTAssertGreaterThan(result.stdout.count, 100_000)
        XCTAssertEqual(result.exitCode, 0)
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

    /// A child that ignores SIGTERM must be killed after the grace period;
    /// the caller must not stay blocked until the hard cap or forever.
    func testCommandIgnoringSigtermIsKilledAfterTheGracePeriod() async {
        let started = Date()

        do {
            _ = try await CommandRunner.run(
                "/bin/sh",
                // `exec` keeps the ignored disposition: a single `sleep`
                // process that ignores SIGTERM and does not hold child pipes.
                arguments: ["-c", "trap '' TERM; exec sleep 60"],
                timeout: 0.5
            )
            XCTFail("Expected CommandRunner to time out.")
        } catch let error as CommandError {
            guard case .timedOut = error else {
                return XCTFail("Expected .timedOut, got \(error).")
            }
        } catch {
            XCTFail("Expected CommandError, got \(error).")
        }

        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(
            elapsed,
            0.5 + CommandRunner.killGrace + CommandRunner.hardCap + 2
        )
    }

    /// `Stop` in the scan workspace cancels the Task; the child process must
    /// be terminated instead of waiting for its timeout.
    func testCancellingTheTaskTerminatesTheCommand() async throws {
        let task = Task {
            try await CommandRunner.run("/bin/sleep", arguments: ["30"], timeout: 60)
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        let started = Date()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the command to be cancelled.")
        } catch is CancellationError {
            // Expected: cancellation is reported as CancellationError.
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }

        // Worst case: the child holds the pipes and the guaranteed resume
        // fires after the kill grace and the hard cap. Normally it is instant.
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            CommandRunner.killGrace + CommandRunner.hardCap + 2
        )
    }
}
