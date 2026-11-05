import Foundation

struct OrphanCollector: Collector {
    let category: ItemCategory = .leftovers

    private let minimumBytes: Int64 = 200 * 1024 * 1024
    private let limit = 10

    private struct Candidate: Sendable {
        let name: String
        let path: String
    }

    private struct Measured: Sendable {
        let candidate: Candidate
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let supportPath = "\(home)/Library/Application Support"
        let installed = installedAppNames()

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: supportPath) else {
            return []
        }

        let candidates = entries
            .filter { !$0.hasPrefix(".") && !$0.hasPrefix("com.apple.") }
            .filter { !hasMatchingApp(entry: $0, installed: installed) }
            .map { Candidate(name: $0, path: "\(supportPath)/\($0)") }

        var measured: [Measured] = []

        await withTaskGroup(of: Measured?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let bytes = await PathSizer.sizeInBytes(of: candidate.path),
                          bytes >= minimumBytes else { return nil }
                    return Measured(candidate: candidate, bytes: bytes)
                }
            }

            for await result in group {
                if let result {
                    measured.append(result)
                }
            }
        }

        return measured
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { item in
                ScanItem(
                    category: .leftovers,
                    title: "Possible leftover: \(item.candidate.name)",
                    detail: "Application Support folder with no clearly matching app. This is a heuristic — review the contents before deleting anything.",
                    impactLabel: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file),
                    impactBytes: item.bytes,
                    risk: .caution,
                    action: .none,
                    evidence: item.candidate.path
                )
            }
    }

    private func installedAppNames() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = ["/Applications", "\(home)/Applications", "/System/Applications"]

        var names: [String] = []
        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            names.append(contentsOf: entries
                .filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) })
        }
        return names
    }

    private func hasMatchingApp(entry: String, installed: [String]) -> Bool {
        let needle = normalize(entry)
        guard needle.count >= 3 else { return true }

        return installed.contains { app in
            let haystack = normalize(app)
            guard haystack.count >= 3 else { return false }
            return haystack == needle || haystack.contains(needle) || needle.contains(haystack)
        }
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
