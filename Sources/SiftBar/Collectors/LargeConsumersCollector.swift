import Foundation

/// Read-only view of the biggest files and folders in the user's content
/// directories. SiftBar never deletes these: it points at the largest
/// consumers so the user can review them in Finder and decide.
struct LargeConsumersCollector: Collector {
    let category: ItemCategory = .disk

    static let minimumBytes: Int64 = 1_000_000_000
    static let limit = 12
    static let directoryNames = ["Downloads", "Desktop", "Documents", "Movies", "Pictures", "Music"]

    struct Entry: Sendable, Equatable {
        let path: String
        let name: String
        let isDirectory: Bool
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = Self.roots(home: home)
            .filter { FileManager.default.fileExists(atPath: $0) }

        var entries: [Entry] = []

        await withTaskGroup(of: [Entry].self) { group in
            for root in roots {
                group.addTask {
                    let sizes = await PathSizer.childSizes(of: root)

                    return sizes.map { size in
                        var isDirectory: ObjCBool = false
                        FileManager.default.fileExists(
                            atPath: size.path,
                            isDirectory: &isDirectory
                        )

                        return Entry(
                            path: size.path,
                            name: URL(fileURLWithPath: size.path).lastPathComponent,
                            isDirectory: isDirectory.boolValue,
                            bytes: size.bytes
                        )
                    }
                }
            }

            for await batch in group {
                entries.append(contentsOf: batch)
            }
        }

        return Self.items(from: entries, home: home)
    }

    /// Only the folders people actually browse for space. Library, system
    /// paths, and caches are handled by their own collectors.
    static func roots(home: String) -> [String] {
        directoryNames.map { "\(home)/\($0)" }
    }

    static func items(from entries: [Entry], limit: Int = limit, home: String = "") -> [ScanItem] {
        entries
            .filter { $0.bytes >= minimumBytes }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { item(for: $0, home: home) }
    }

    static func item(for entry: Entry, home: String) -> ScanItem {
        let kind = entry.isDirectory ? "folder" : "file"
        let location = abbreviate(entry.path, home: home)

        return ScanItem(
            category: .disk,
            title: "Large \(kind): \(entry.name)",
            detail: "\(format(entry.bytes)) in \(location). Review in Finder before deleting anything; SiftBar will not remove it for you.",
            impactLabel: format(entry.bytes),
            impactBytes: entry.bytes,
            risk: .caution,
            action: .none,
            evidence: entry.path
        )
    }

    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
