import Darwin
import Foundation

struct StartupCollector: Collector {
    let category: ItemCategory = .startup

    static let failingLimit = 12
    static let launchItemLimit = 30

    func collect() async -> [ScanItem] {
        var items: [ScanItem] = []
        items.append(contentsOf: await failingItems())

        let disabled = await Self.disabledLabels()
        items.append(contentsOf: Self.launchItems(in: Self.defaultDirectories(), disabled: disabled))
        return items
    }

    static func defaultDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons"
        ]
    }

    private func failingItems() async -> [ScanItem] {
        guard let result = try? await CommandRunner.run(
            "/bin/launchctl",
            arguments: ["list"],
            timeout: 10
        ), result.exitCode == 0 else { return [] }

        return Self.parseFailingItems(result.stdout)
    }

    /// Parses `launchctl list` output. Apple agents are skipped because macOS
    /// manages them and they often report transient SIGKILL exit statuses.
    static func parseFailingItems(_ output: String, limit: Int = failingLimit) -> [ScanItem] {
        var items: [ScanItem] = []

        for line in output.split(separator: "\n") {
            let parts = line
                .split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard parts.count >= 3 else { continue }

            let status = parts[1]
            let label = parts[2]

            // Header row: PID <tab> Status <tab> Label
            guard parts[0] != "PID" else { continue }
            guard !label.isEmpty else { continue }
            guard !label.hasPrefix("com.apple.") else { continue }
            guard status != "0", status != "-" else { continue }

            items.append(ScanItem(
                category: .startup,
                title: "Failing launch item: \(label)",
                detail: "launchctl reports last exit status \(status). Review whether this agent is still needed.",
                impactLabel: "exit \(status)",
                impactBytes: nil,
                risk: .caution,
                action: .disableLaunchItem(label: label),
                evidence: "launchctl list"
            ))

            if items.count >= limit { break }
        }

        return items
    }

    /// Labels the user already disabled. Without this, a disabled launch item
    /// would keep showing up because its plist still exists on disk.
    private static func disabledLabels() async -> Set<String> {
        guard let result = try? await CommandRunner.run(
            "/bin/launchctl",
            arguments: ["print-disabled", "gui/\(getuid())"],
            timeout: 10
        ), result.exitCode == 0 else { return [] }

        return parseDisabledLabels(result.stdout)
    }

    static func parseDisabledLabels(_ output: String) -> Set<String> {
        var labels = Set<String>()

        for line in output.split(separator: "\n") {
            let parts = line
                .split(separator: "=>", maxSplits: 1, omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard parts.count == 2, parts[1].hasPrefix("disabled") else { continue }
            labels.insert(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }

        return labels
    }

    /// Lists third-party launch agents and daemons found in the given folders.
    static func launchItems(
        in directories: [String],
        limit: Int = launchItemLimit,
        disabled: Set<String> = [],
        fileManager: FileManager = .default
    ) -> [ScanItem] {
        var items: [ScanItem] = []
        var seen = Set<String>()

        for directory in directories {
            guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }

            for file in files.sorted() where file.hasSuffix(".plist") {
                let label = String(file.dropLast(".plist".count))
                guard !label.hasPrefix("com.apple.") else { continue }
                guard !disabled.contains(label) else { continue }
                guard seen.insert(label).inserted else { continue }

                items.append(ScanItem(
                    category: .startup,
                    title: "Launch item: \(label)",
                    detail: "Registered in \(directory). Disable it only if the related app or service is no longer needed.",
                    impactLabel: "launch agent",
                    impactBytes: nil,
                    risk: risk(forDirectory: directory),
                    action: .disableLaunchItem(label: label),
                    evidence: directory
                ))

                if items.count >= limit { return items }
            }
        }

        return items
    }

    /// User agents are reversible without privileges. System-wide agents and
    /// daemons require admin rights, so they deserve extra attention.
    static func risk(forDirectory directory: String) -> Risk {
        directory.hasPrefix("/Library/") ? .caution : .safe
    }
}
