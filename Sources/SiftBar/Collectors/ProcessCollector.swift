import Foundation

struct ProcessCollector: Collector {
    let category: ItemCategory = .processes

    private let minimumBytes: Int64 = 150 * 1024 * 1024
    private let limit = 12

    private struct Entry {
        let pid: Int32
        let user: String
        let bytes: Int64
        let command: String
    }

    func collect() async -> [ScanItem] {
        guard let result = try? await CommandRunner.run(
            "/bin/ps",
            arguments: ["-Ao", "pid=,user=,rss=,comm="],
            timeout: 10
        ), result.exitCode == 0 else { return [] }

        var entries: [Entry] = []
        for line in result.stdout.split(separator: "\n") {
            let parts = line
                .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                .map(String.init)

            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let rssKilobytes = Int64(parts[2]) else { continue }

            entries.append(Entry(
                pid: pid,
                user: parts[1],
                bytes: rssKilobytes * 1024,
                command: parts[3]
            ))
        }

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
            let name = (entry.command as NSString).lastPathComponent
            let risk: Risk = entry.bytes >= 1_000_000_000 ? .caution : .safe

            items.append(ScanItem(
                category: .processes,
                title: name,
                detail: "PID \(entry.pid) · \(entry.user) · \(formatted(entry.bytes)) resident",
                impactLabel: formatted(entry.bytes),
                impactBytes: entry.bytes,
                risk: risk,
                action: .killProcess(pid: entry.pid, name: name),
                evidence: "ps -Ao pid,user,rss,comm"
            ))
        }

        return items
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
