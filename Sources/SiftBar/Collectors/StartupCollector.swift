import Foundation

struct StartupCollector: Collector {
    let category: ItemCategory = .startup

    func collect() async -> [ScanItem] {
        var items: [ScanItem] = []
        items.append(contentsOf: await failingItems())
        items.append(contentsOf: await thirdPartyLaunchItems(limit: 30))
        return items
    }

    private func failingItems() async -> [ScanItem] {
        guard let result = try? await CommandRunner.run(
            "/bin/launchctl",
            arguments: ["list"],
            timeout: 10
        ), result.exitCode == 0 else { return [] }

        var items: [ScanItem] = []
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let parts = line
                .split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard parts.count >= 3 else { continue }
            let status = parts[1]
            let label = parts[2]

            // Apple agents are managed by macOS and often report transient
            // SIGKILL statuses; surfacing them would only create noise.
            guard !label.hasPrefix("com.apple.") else { continue }
            guard !label.isEmpty, status != "0", status != "-" else { continue }

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

            if items.count >= 12 { break }
        }
        return items
    }

    private func thirdPartyLaunchItems(limit: Int) async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = [
            "\(home)/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons"
        ]

        var items: [ScanItem] = []
        var seen = Set<String>()

        for directory in directories {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }

            for file in files.sorted() where file.hasSuffix(".plist") {
                let label = String(file.dropLast(".plist".count))
                guard !label.hasPrefix("com.apple.") else { continue }
                guard seen.insert(label).inserted else { continue }

                items.append(ScanItem(
                    category: .startup,
                    title: "Launch item: \(label)",
                    detail: "Registered in \(directory). Disable it only if the related app or service is no longer needed.",
                    impactLabel: "launch agent",
                    impactBytes: nil,
                    risk: .safe,
                    action: .disableLaunchItem(label: label),
                    evidence: directory
                ))

                if items.count >= limit { return items }
            }
        }

        return items
    }
}
