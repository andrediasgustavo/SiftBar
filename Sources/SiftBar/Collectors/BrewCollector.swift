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

        var items: [ScanItem] = []

        for line in result.stdout.split(separator: "\n").dropFirst() {
            let parts = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            guard parts.count >= 2 else { continue }

            let name = parts[0]
            let status = parts[1]
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
