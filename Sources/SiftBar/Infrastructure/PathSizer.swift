import Foundation

enum PathSizer {
    struct ChildSize: Sendable, Equatable {
        let path: String
        let bytes: Int64
    }

    /// Returns the allocated size of a path in bytes, or nil when it does not exist.
    ///
    /// A recent measurement with the same directory signature is reused so the
    /// post-action refresh does not walk the same tree again.
    ///
    /// `ignoringNames` is passed to `du -I`: useful for folders whose name is
    /// expensive to walk and not needed here (for example Xcode's simulator
    /// runtimes inside a system folder).
    static func sizeInBytes(
        of path: String,
        timeout: TimeInterval = 20,
        cache: SizeCache = .shared,
        ignoringNames: [String] = []
    ) async -> Int64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let signature = modificationDate(of: path)
        if let cached = cache.lookup(path: path, signature: signature) {
            return cached
        }

        var arguments = ["-sk"]
        for name in ignoringNames {
            arguments.append("-I")
            arguments.append(name)
        }
        arguments.append(path)

        guard let result = try? await CommandRunner.run(
            "/usr/bin/du",
            arguments: arguments,
            timeout: timeout
        ) else { return nil }

        guard let bytes = parseDU(result.stdout) else { return nil }
        cache.store(path: path, bytes: bytes, signature: signature)
        return bytes
    }

    private static func modificationDate(of path: String) -> Date {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date else {
            return .distantPast
        }
        return date
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

    /// Maximum number of `du` processes spawned at once by `sizesOfChildren`.
    /// A folder such as `~/Library/Containers` can contain hundreds of entries;
    /// one process per entry at the same time makes the whole Mac sluggish.
    static let maxConcurrentDu = 8

    /// Sum of the immediate children of a directory, skipping names that would
    /// trigger sensitive permission prompts (for example a Photos container).
    ///
    /// The children are measured in bounded chunks so the scan never spawns a
    /// process per entry at once.
    static func sizesOfChildren(
        of path: String,
        excludingNames: Set<String> = [],
        timeout: TimeInterval = 20
    ) async -> Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return 0
        }

        let allowed = entries
            .filter { !$0.hasPrefix(".") }
            .filter { !excludingNames.contains($0.lowercased()) }
            .map { "\(path)/\($0)" }

        var total: Int64 = 0
        var index = 0
        while index < allowed.count {
            let end = min(index + maxConcurrentDu, allowed.count)
            let chunk = Array(allowed[index..<end])

            await withTaskGroup(of: Int64.self) { group in
                for child in chunk {
                    group.addTask {
                        await sizeInBytes(of: child, timeout: timeout) ?? 0
                    }
                }

                for await size in group {
                    total += size
                }
            }

            index = end
        }
        return total
    }

    /// Sizes of the immediate child directories of a directory, without the
    /// extra `find` pass used by `childSizes`. Used by the space-map collector,
    /// where only directory totals are needed and process load matters.
    ///
    /// `excludingNames` filters children by their last path component
    /// (lowercased), which keeps the sensitive Photos containers out of the
    /// walk without opening them.
    static func childDirectorySizes(
        of path: String,
        excludingNames: Set<String> = [],
        timeout: TimeInterval = 15
    ) async -> [ChildSize] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        guard let result = try? await CommandRunner.run(
            "/usr/bin/du",
            arguments: ["-d", "1", "-k", path],
            timeout: timeout
        ) else { return [] }

        return parseChildSizes(result.stdout, root: path).filter { child in
            !excludingNames.contains(
                URL(fileURLWithPath: child.path).lastPathComponent.lowercased()
            )
        }
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
