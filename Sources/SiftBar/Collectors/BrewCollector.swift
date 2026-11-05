import Foundation

struct BrewCollector: Collector {
    let category: ItemCategory = .services

    func collect() async -> [ScanItem] {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brew = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return []
        }

        guard let result = try? await CommandRunner.run(
            brew,
            arguments: ["services", "list"],
            timeout: 20
        ), result.exitCode == 0 else { return [] }

        return Self.parse(result.stdout)
    }

    /// Parses `brew services list`. Only running, errored, or scheduled
    /// services are reported; stopped services need no attention.
    static func parse(_ output: String) -> [ScanItem] {
        var items: [ScanItem] = []

        for line in output.split(separator: "\n") {
            let parts = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            guard parts.count >= 2 else { continue }

            let name = parts[0]
            let status = parts[1]

            // Header row: Name Status User File
            guard name != "Name" else { continue }
            guard status == "started" || status == "error" || status == "scheduled" else { continue }

            let user = parts.count >= 3 ? parts[2] : "-"
            let risk: Risk = status == "error" ? .caution : .safe
            let detail = status == "error"
                ? "The service reports an error. Review or stop it."
                : "Runs automatically at login. Stop it if you do not need it every session."

            items.append(ScanItem(
                category: .services,
                title: "Homebrew service: \(name)",
                detail: "\(detail) User: \(user).",
                impactLabel: status,
                impactBytes: nil,
                risk: risk,
                action: .stopService(name: name),
                evidence: "brew services list"
            ))
        }

        return items
    }
}
