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
    /// Runs an executable without a shell, so arguments cannot be injected.
    ///
    /// Output is drained while the process runs. Reading only in the
    /// termination handler deadlocks as soon as a command writes more than the
    /// pipe buffer (about 64 KB), which is common for `ps` listings.
    static func run(
        _ executable: String,
        arguments: [String] = [],
        timeout: TimeInterval = 10
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let resumeGuard = ResumeGuard()
            let timeoutFlag = TimeoutFlag()

            let timeoutItem = DispatchWorkItem {
                guard process.isRunning else { return }
                timeoutFlag.markTimedOut()
                process.terminate()
            }
            DispatchQueue.global(qos: .userInitiated)
                .asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                resumeGuard.perform {
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                }
                return
            }

            // Drain both pipes before waiting for the process. This prevents
            // the child from blocking on a full pipe buffer.
            DispatchQueue.global(qos: .userInitiated).async {
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeoutItem.cancel()

                if timeoutFlag.didTimeOut {
                    resumeGuard.perform {
                        continuation.resume(throwing: CommandError.timedOut(timeout))
                    }
                    return
                }

                resumeGuard.perform {
                    continuation.resume(returning: CommandResult(
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    ))
                }
            }
        }
    }
}

private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func perform(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return }
        didResume = true
        body()
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
