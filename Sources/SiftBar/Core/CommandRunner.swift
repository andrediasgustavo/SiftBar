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

            let timeoutItem = DispatchWorkItem {
                guard process.isRunning else { return }
                process.terminate()
                resumeGuard.perform {
                    continuation.resume(throwing: CommandError.timedOut(timeout))
                }
            }
            DispatchQueue.global(qos: .userInitiated)
                .asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { finished in
                timeoutItem.cancel()

                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                resumeGuard.perform {
                    continuation.resume(returning: CommandResult(
                        stdout: String(data: stdout, encoding: .utf8) ?? "",
                        stderr: String(data: stderr, encoding: .utf8) ?? "",
                        exitCode: finished.terminationStatus
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                resumeGuard.perform {
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
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
