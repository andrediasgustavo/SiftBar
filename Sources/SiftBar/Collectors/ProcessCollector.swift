import Foundation

struct ProcessCollector: Collector {
    let category: ItemCategory = .processes

    static let minimumBytes: Int64 = 150 * 1024 * 1024
    static let limit = 12

    struct Entry: Sendable, Equatable {
        let pid: Int32
        let user: String
        let bytes: Int64
        let command: String

        var name: String {
            (command as NSString).lastPathComponent
        }
    }

    func collect() async -> [ScanItem] {
        guard let result = try? await CommandRunner.run(
            "/bin/ps",
            arguments: ["-Ao", "pid=,user=,rss=,comm="],
            timeout: 10
        ), result.exitCode == 0 else { return [] }

        return Self.items(from: Self.parse(result.stdout))
    }

    /// Parses `ps -Ao pid=,user=,rss=,comm=` output. Malformed lines are skipped.
    static func parse(_ output: String) -> [Entry] {
        var entries: [Entry] = []

        for line in output.split(separator: "\n") {
            let parts = line
                .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                .map(String.init)

            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let rssKilobytes = Int64(parts[2]),
                  rssKilobytes >= 0 else { continue }

            entries.append(Entry(
                pid: pid,
                user: parts[1],
                bytes: rssKilobytes * 1024,
                command: parts[3]
            ))
        }

        return entries
    }

    static func items(from entries: [Entry]) -> [ScanItem] {
        var items: [ScanItem] = [
            ScanItem(
                category: .processes,
                title: "\(entries.count) processes running",
                detail: "Only processes above 150 MB are listed below. Sort order is by resident memory.",
                impactLabel: "\(entries.count) processes",
                impactBytes: nil,
                risk: .safe,
                action: .none,
                evidence: "ps -Ao pid,user,rss,comm"
            )
        ]

        let heavy = entries
            .filter { $0.bytes >= minimumBytes }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)

        for entry in heavy {
            items.append(ScanItem(
                category: .processes,
                title: entry.name,
                detail: "PID \(entry.pid) · \(entry.user) · \(format(entry.bytes)) resident",
                impactLabel: format(entry.bytes),
                impactBytes: entry.bytes,
                risk: risk(for: entry.bytes),
                action: .killProcess(pid: entry.pid, name: entry.name),
                evidence: "ps -Ao pid,user,rss,comm"
            ))
        }

        return items
    }

    /// Processes at or above 1 GB are flagged as caution because quitting them
    /// can lose unsaved work; smaller ones are informational.
    static func risk(for bytes: Int64) -> Risk {
        bytes >= 1_000_000_000 ? .caution : .safe
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
