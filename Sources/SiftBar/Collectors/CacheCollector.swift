import Foundation

struct CacheCollector: Collector {
    let category: ItemCategory = .caches

    static let minimumBytes: Int64 = 20 * 1024 * 1024

    struct Target: Sendable, Equatable {
        let name: String
        let path: String
        let risk: Risk
        /// Executable names (lowercased for matching) that use this cache. If
        /// one is running, the item carries a warning so the user can quit the
        /// app before moving its data to the Trash.
        let relatedApps: [String]

        init(name: String, path: String, risk: Risk, relatedApps: [String] = []) {
            self.name = name
            self.path = path
            self.risk = risk
            self.relatedApps = relatedApps
        }
    }

    struct Measured: Sendable, Equatable {
        let target: Target
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let targets = Self.targets(home: home)
        let running = await RunningProcesses.names()

        var measured: [Measured] = []

        await withTaskGroup(of: Measured?.self) { group in
            for target in targets {
                group.addTask {
                    guard let bytes = await PathSizer.sizeInBytes(of: target.path),
                          bytes >= Self.minimumBytes else { return nil }
                    return Measured(target: target, bytes: bytes)
                }
            }

            for await result in group {
                if let result {
                    measured.append(result)
                }
            }
        }

        return Self.items(from: measured, running: running)
    }

    static func targets(home: String) -> [Target] {
        [
            Target(name: "npm", path: "\(home)/.npm/_cacache", risk: .safe),
            Target(name: "Expo", path: "\(home)/.expo", risk: .safe, relatedApps: ["expo"]),
            Target(
                name: "Xcode DerivedData",
                path: "\(home)/Library/Developer/Xcode/DerivedData",
                risk: .safe,
                relatedApps: ["xcode"]
            ),
            Target(name: "Gradle", path: "\(home)/.gradle/caches", risk: .safe),
            Target(name: "Homebrew", path: "\(home)/Library/Caches/Homebrew", risk: .safe),
            Target(
                name: "CoreSimulator (user)",
                path: "\(home)/Library/Developer/CoreSimulator/Caches",
                risk: .safe,
                relatedApps: ["simulator", "coresimulatorbridge"]
            ),
            Target(
                name: "CoreSimulator (system)",
                path: "/Library/Developer/CoreSimulator/Caches",
                risk: .caution,
                relatedApps: ["simulator", "coresimulatorbridge"]
            ),
            Target(name: "General", path: "\(home)/Library/Caches", risk: .caution)
        ]
    }

    static func items(from measured: [Measured], running: Set<String> = []) -> [ScanItem] {
        measured
            .sorted { $0.bytes > $1.bytes }
            .map { item in
                ScanItem(
                    category: .caches,
                    title: item.target.name.lowercased().hasSuffix("cache")
                        ? item.target.name
                        : "\(item.target.name) cache",
                    detail: "Recreatable cache data. Deleting it may slow the next run of the related tool, but does not remove personal files.",
                    impactLabel: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file),
                    impactBytes: item.bytes,
                    risk: item.target.risk,
                    action: .deletePath(path: item.target.path, bytes: item.bytes),
                    evidence: "du -sk \(item.target.path)",
                    warning: warning(for: item.target, running: running)
                )
            }
    }

    /// Warn only when an app that actually uses this cache is open. Executable
    /// names are matched lowercase and shown with a friendly display name.
    static func warning(for target: Target, running: Set<String>) -> String? {
        let active = target.relatedApps.filter { running.contains($0.lowercased()) }
        guard !active.isEmpty else { return nil }

        let names = active
            .map { displayName(for: $0) }
            .joined(separator: " and ")
        let verb = active.count == 1 ? "is" : "are"
        let pronoun = active.count == 1 ? "it" : "them"

        return "\(names) \(verb) running. Quit \(pronoun) before moving this cache to the Trash."
    }

    static func displayName(for process: String) -> String {
        switch process.lowercased() {
        case "xcode": return "Xcode"
        case "simulator": return "Simulator"
        case "coresimulatorbridge": return "CoreSimulatorBridge"
        case "expo": return "Expo"
        default:
            return String(process.prefix(1)).uppercased() + String(process.dropFirst())
        }
    }
}
