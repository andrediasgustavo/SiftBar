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

    /// Processes sharing an executable name are shown as one row to avoid
    /// flooding the list with dozens of identical helpers.
    struct Group: Sendable, Equatable {
        let name: String
        var entries: [Entry]

        var bytes: Int64 {
            entries.reduce(0) { $0 + $1.bytes }
        }

        var isProtected: Bool {
            entries.contains { ProcessSafety.isProtected($0) }
        }

        var risk: Risk {
            if isProtected { return .dangerous }
            return ProcessCollector.risk(for: bytes)
        }

        var userLabel: String {
            let users = Set(entries.map(\.user))
            return users.count == 1 ? (users.first ?? "-") : "multiple users"
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
                detail: "Only processes above 150 MB are listed below. Processes sharing an executable are grouped and sorted by total resident memory.",
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

        let grouped = groups(from: Array(heavy))
            .sorted { $0.bytes > $1.bytes }

        for group in grouped {
            items.append(item(for: group))
        }

        return items
    }

    static func groups(from entries: [Entry]) -> [Group] {
        var groups: [Group] = []
        var indexByName: [String: Int] = [:]

        for entry in entries {
            if let index = indexByName[entry.name] {
                groups[index].entries.append(entry)
            } else {
                indexByName[entry.name] = groups.count
                groups.append(Group(name: entry.name, entries: [entry]))
            }
        }

        return groups
    }

    static func item(for group: Group) -> ScanItem {
        let count = group.entries.count
        let protectedSuffix = group.isProtected
            ? " Protected system process — SiftBar will never terminate it."
            : ""

        let detail: String
        let action: ItemAction

        if count == 1, let entry = group.entries.first {
            detail = "PID \(entry.pid) · \(entry.user) · \(format(entry.bytes)) resident.\(protectedSuffix)"
            action = group.isProtected
                ? .none
                : .killProcess(pid: entry.pid, name: entry.name)
        } else {
            detail = "\(count) processes · \(group.userLabel) · \(format(group.bytes)) resident. Expand to quit individual processes.\(protectedSuffix)"
            // The group itself is not actionable; each child carries one PID.
            action = .none
        }

        let children = count > 1
            ? group.entries.map { child(for: $0, in: group) }
            : []

        return ScanItem(
            category: .processes,
            title: group.name,
            detail: detail,
            impactLabel: format(group.bytes),
            impactBytes: group.bytes,
            risk: group.risk,
            action: action,
            evidence: "ps -Ao pid,user,rss,comm",
            children: children
        )
    }

    static func child(for entry: Entry, in group: Group) -> ScanItem {
        let protected = ProcessSafety.isProtected(entry)
        let protectedSuffix = protected
            ? " Protected system process — SiftBar will never terminate it."
            : ""

        return ScanItem(
            category: .processes,
            title: "\(group.name) · PID \(entry.pid)",
            detail: "PID \(entry.pid) · \(entry.user) · \(format(entry.bytes)) resident.\(protectedSuffix)",
            impactLabel: format(entry.bytes),
            impactBytes: entry.bytes,
            risk: protected ? .dangerous : risk(for: entry.bytes),
            action: protected ? .none : .killProcess(pid: entry.pid, name: entry.name),
            evidence: "ps -Ao pid,user,rss,comm"
        )
    }

    /// Non-protected processes at or above 1 GB are flagged as caution because
    /// quitting them can lose unsaved work.
    static func risk(for bytes: Int64) -> Risk {
        bytes >= 1_000_000_000 ? .caution : .safe
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
