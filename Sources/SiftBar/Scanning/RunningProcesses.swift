import Foundation

/// Answers "is this app running?" for collectors that want to warn before
/// removing data an app may be using.
enum RunningProcesses {
    static func names() async -> Set<String> {
        guard let result = try? await CommandRunner.run(
            "/bin/ps",
            arguments: ["-Ao", "comm="],
            timeout: 10
        ), result.exitCode == 0 else { return [] }

        return parse(result.stdout)
    }

    /// Lowercased executable names, e.g. `Xcode` -> `xcode`.
    static func parse(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value).lastPathComponent.lowercased()
        })
    }
}
