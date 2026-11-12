import Darwin
import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum CommandError: Error, LocalizedError {
    case launchFailed(String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Failed to launch command: \(message)"
        case .timedOut(let seconds):
            return "Command timed out after \(Int(seconds)) seconds."
        }
    }
}

enum CommandRunner {
    /// Grace period between SIGTERM and SIGKILL. Most children exit on SIGTERM;
    /// `du` stuck on a slow network mount may not.
    static let killGrace: TimeInterval = 2
    /// After the SIGKILL, how long to wait for the pipes to close before the
    /// caller is released. A child holding the pipe (e.g. a `find -exec du`)
    /// can outlive its parent, so this hard cap keeps the scan responsive.
    static let hardCap: TimeInterval = 5

    /// Runs an executable without a shell, so arguments cannot be injected.
    ///
    /// Output is drained while the process runs. Reading only in the
    /// termination handler deadlocks as soon as a command writes more than the
    /// pipe buffer (about 64 KB), which is common for `ps` listings.
    ///
    /// Timeouts and cancellation escalate: SIGTERM, then SIGKILL after
    /// `killGrace`, then a hard cap that releases the caller even if a child
    /// still holds the pipe.
    static func run(
        _ executable: String,
        arguments: [String] = [],
        timeout: TimeInterval = 10
    ) async throws -> CommandResult {
        if Task.isCancelled { throw CancellationError() }

        let box = ProcessBox()
        let continuationBox = ContinuationBox()

        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                let process = box.process
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                continuationBox.set(continuation)
                let timeoutFlag = TimeoutFlag()
                let queue = DispatchQueue.global(qos: .userInitiated)

                let terminateItem = DispatchWorkItem {
                    guard process.isRunning else { return }
                    timeoutFlag.markTimedOut()
                    process.terminate()
                }
                let killItem = DispatchWorkItem {
                    guard process.isRunning else { return }
                    kill(process.processIdentifier, SIGKILL)
                }
                let hardItem = DispatchWorkItem {
                    // The child may still hold the pipe (for example a `du`
                    // spawned by `find`). Never leave the caller waiting on it.
                    continuationBox.resume(with: .failure(CommandError.timedOut(timeout)))
                }

                queue.asyncAfter(deadline: .now() + timeout, execute: terminateItem)
                queue.asyncAfter(deadline: .now() + timeout + Self.killGrace, execute: killItem)
                queue.asyncAfter(
                    deadline: .now() + timeout + Self.killGrace + Self.hardCap,
                    execute: hardItem
                )

                // Cancellation can land between the `isCancelled` check at the
                // top of `run` and the installation of the cancellation
                // handler. Do not launch (or keep) a child in that window, or
                // the caller would wait for the full timeout.
                if Task.isCancelled {
                    terminateItem.cancel()
                    killItem.cancel()
                    hardItem.cancel()
                    continuationBox.resume(with: .failure(CancellationError()))
                    return
                }

                do {
                    try process.run()
                } catch {
                    terminateItem.cancel()
                    killItem.cancel()
                    hardItem.cancel()
                    continuationBox.resume(
                        with: .failure(CommandError.launchFailed(error.localizedDescription))
                    )
                    return
                }

                if Task.isCancelled {
                    process.terminate()
                    queue.asyncAfter(deadline: .now() + Self.killGrace) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }

                // Drain both pipes before waiting for the process. This prevents
                // the child from blocking on a full pipe buffer.
                queue.async {
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    terminateItem.cancel()
                    killItem.cancel()
                    hardItem.cancel()

                    if timeoutFlag.didTimeOut {
                        continuationBox.resume(with: .failure(CommandError.timedOut(timeout)))
                        return
                    }

                    continuationBox.resume(with: .success(CommandResult(
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    )))
                }
            }
        } onCancel: {
            // `Stop` in the scan workspace cancels the task; terminating the
            // child makes `du` return immediately instead of waiting for its
            // timeout. A child that ignores SIGTERM is killed after the grace
            // period.
            let process = box.process
            if process.isRunning {
                process.terminate()

                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.killGrace) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }

            // Hard guarantee: cancellation never waits for a stuck pipe (a
            // grandchild of `find -exec du` can keep the file handle open).
            // If the reader has not completed by now, resume directly.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + Self.killGrace + Self.hardCap
            ) {
                continuationBox.resume(with: .failure(CancellationError()))
            }
        }

        if Task.isCancelled { throw CancellationError() }
        return result
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
}

/// Single-resume guard shared by the reader, the timeout escalation and the
/// cancellation handler. The first resume wins; later ones are no-ops.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CommandResult, Error>?
    private var didResume = false

    func set(_ continuation: CheckedContinuation<CommandResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(with result: Result<CommandResult, Error>) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        let stored = continuation
        self.continuation = nil
        lock.unlock()
        stored.resume(with: result)
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        timedOut = true
    }
}
