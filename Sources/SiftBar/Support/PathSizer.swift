import Foundation

enum PathSizer {
    /// Returns the allocated size of a path in bytes, or nil when it does not exist.
    static func sizeInBytes(of path: String, timeout: TimeInterval = 20) async -> Int64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let result = try? await CommandRunner.run(
            "/usr/bin/du",
            arguments: ["-sk", path],
            timeout: timeout
        ) else { return nil }

        return parseDU(result.stdout)
    }

    /// Parses the kilobyte count from `du -sk` output and converts it to bytes.
    static func parseDU(_ output: String) -> Int64? {
        let field = output
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
            .first ?? ""

        guard let kilobytes = Int64(field), kilobytes >= 0 else { return nil }
        return kilobytes * 1024
    }
}
