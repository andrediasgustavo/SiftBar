import Foundation

/// Narrow seam around `CommandRunner` so action paths can be tested without
/// launching real processes (and without touching real simulators).
protocol CommandExecuting: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult
}

struct SystemCommandExecutor: CommandExecuting {
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        try await CommandRunner.run(executable, arguments: arguments, timeout: timeout)
    }
}
