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

        let field = result.stdout
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
            .first ?? ""

        guard let kilobytes = Int64(field) else { return nil }
        return kilobytes * 1024
    }
}
