import Foundation

enum PathSizer {
    struct ChildSize: Sendable, Equatable {
        let path: String
        let bytes: Int64
    }

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

    /// Sizes of the immediate children of a directory (files and folders).
    /// A single `du -d 1` call is much cheaper than one `du` per child.
    static func childSizes(of path: String, timeout: TimeInterval = 15) async -> [ChildSize] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        guard let result = try? await CommandRunner.run(
            "/usr/bin/du",
            arguments: ["-d", "1", "-k", path],
            timeout: timeout
        ) else { return [] }

        return parseChildSizes(result.stdout, root: path)
    }

    /// Parses `du -k -d 1 <root>` output, skipping the root line itself.
    static func parseChildSizes(_ output: String, root: String) -> [ChildSize] {
        let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
        var seen = Set<String>()
        var sizes: [ChildSize] = []

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let kilobytes = Int64(parts[0]),
                  kilobytes >= 0 else { continue }

            let childPath = URL(fileURLWithPath: String(parts[1]))
                .standardizedFileURL
                .path

            guard childPath != rootPath, seen.insert(childPath).inserted else { continue }
            sizes.append(ChildSize(path: childPath, bytes: kilobytes * 1024))
        }

        return sizes
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
