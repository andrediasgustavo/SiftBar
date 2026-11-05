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
    ///
    /// macOS `du -d 1` only prints directories, so directories come from `du`
    /// and direct files come from a shallow `find` (limited by the size
    /// threshold). This avoids `du -a`, which prints the whole tree and can
    /// time out on large folders.
    static func childSizes(
        of path: String,
        minimumFileBytes: Int64 = 0,
        timeout: TimeInterval = 15
    ) async -> [ChildSize] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        async let directories = directorySizes(of: path, timeout: timeout)
        async let files = fileSizes(in: path, minimumBytes: minimumFileBytes, timeout: timeout)

        let all = await directories + files
        var seen = Set<String>()
        return all.filter { seen.insert($0.path).inserted }
    }

    private static func directorySizes(of path: String, timeout: TimeInterval) async -> [ChildSize] {
        guard let result = try? await CommandRunner.run(
            "/usr/bin/du",
            arguments: ["-d", "1", "-k", path],
            timeout: timeout
        ) else { return [] }

        return parseChildSizes(result.stdout, root: path)
    }

    private static func fileSizes(
        in path: String,
        minimumBytes: Int64,
        timeout: TimeInterval
    ) async -> [ChildSize] {
        guard let result = try? await CommandRunner.run(
            "/usr/bin/find",
            arguments: [
                path,
                "-maxdepth", "1",
                "-type", "f",
                "-size", "+\(max(minimumBytes, 1))c",
                "-exec", "/usr/bin/du", "-sk", "{}", "+"
            ],
            timeout: timeout
        ) else { return [] }

        return parseChildSizes(result.stdout, root: path)
    }

    /// Parses `du` output, keeping only immediate children of the root.
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

            guard URL(fileURLWithPath: childPath).deletingLastPathComponent().path == rootPath else {
                continue
            }
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
