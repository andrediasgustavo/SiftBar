import Foundation

struct OrphanCollector: Collector {
    let category: ItemCategory = .leftovers

    static let minimumBytes: Int64 = 200 * 1024 * 1024
    static let limit = 10

    /// Apple/cloud folders that look like app names but are system data. They
    /// must never be offered as leftovers, even when no matching app exists.
    static let systemOwnedNames: Set<String> = [
        "clouddocs",
        "fileprovider",
        "knowledge",
        "callhistorydb",
        "addressbook",
        "calendars",
        "messages",
        "mail",
        "safari",
        "icloud",
        "ubiquity",
        "sharedfilelist",
        "dock",
        "spotlight",
        "homekit",
        "photos"
    ]

    struct Candidate: Sendable, Equatable {
        let name: String
        let path: String
    }

    struct Measured: Sendable {
        let candidate: Candidate
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let supportPath = "\(home)/Library/Application Support"
        let installed = Self.installedAppNames()

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: supportPath) else {
            return []
        }

        let candidates = Self.candidates(
            entries: entries,
            installed: installed,
            supportPath: supportPath
        )

        var measured: [Measured] = []

        await withTaskGroup(of: Measured?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let bytes = await PathSizer.sizeInBytes(of: candidate.path),
                          bytes >= Self.minimumBytes else { return nil }
                    return Measured(candidate: candidate, bytes: bytes)
                }
            }

            for await result in group {
                if let result {
                    measured.append(result)
                }
            }
        }

        return Self.items(from: measured)
    }

    static func items(from measured: [Measured], limit: Int = OrphanCollector.limit) -> [ScanItem] {
        measured
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { item in
                ScanItem(
                    category: .leftovers,
                    title: "Possible leftover: \(item.candidate.name)",
                    detail: "No app named \(item.candidate.name) is installed in /Applications, ~/Applications or /System/Applications. This folder can contain settings, history, saved games, or licenses, so it is not the same as a cache. Open it in Finder before deleting.",
                    impactLabel: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file),
                    impactBytes: item.bytes,
                    risk: .caution,
                    action: .trashLeftover(path: item.candidate.path, bytes: item.bytes),
                    evidence: item.candidate.path,
                    warning: "Review the contents first. This is app data, not recreatable cache.",
                    isInformational: false
                )
            }
    }

    /// Filters Application Support entries that look like they belong to an
    /// installed app. Hidden entries and Apple folders are never candidates.
    static func candidates(
        entries: [String],
        installed: [String],
        supportPath: String
    ) -> [Candidate] {
        entries
            .filter { !$0.hasPrefix(".") && !$0.lowercased().hasPrefix("com.apple.") }
            .filter { !isSystemOwned($0) }
            .filter { !hasMatchingApp(entry: $0, installed: installed) }
            .map { Candidate(name: $0, path: "\(supportPath)/\($0)") }
    }

    static func isSystemOwned(_ entry: String) -> Bool {
        systemOwnedNames.contains(normalize(entry))
    }

    static func installedAppNames(
        directories: [String] = defaultAppDirectories(),
        fileManager: FileManager = .default
    ) -> [String] {
        var names: [String] = []
        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            names.append(contentsOf: entries
                .filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) })
        }
        return names
    }

    static func defaultAppDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "\(home)/Applications", "/System/Applications"]
    }

    static func hasMatchingApp(entry: String, installed: [String]) -> Bool {
        let needle = normalize(entry)
        // Very short folder names match too many apps; treat them as owned so
        // they are never reported as leftovers.
        guard needle.count >= 3 else { return true }

        return installed.contains { app in
            let haystack = normalize(app)
            guard haystack.count >= 3 else { return false }
            return haystack == needle || haystack.contains(needle) || needle.contains(haystack)
        }
    }

    static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
