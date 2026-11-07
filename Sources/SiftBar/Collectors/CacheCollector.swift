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
        // The broad `~/Library/Caches` target is replaced by one row per app
        // cache, so the result is actionable instead of a single blob.
        let targets = Self.targets(home: home).filter { $0.name != "General" }
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

        measured.append(contentsOf: await Self.dynamicMeasured(
            home: home,
            excluding: Set(targets.map(\.path))
        ))

        return Self.items(from: Self.removingNestedOverlap(measured), running: running)
    }

    /// One row per top-level app cache in `~/Library/Caches`, measured with a
    /// single `du -d 1` instead of one process per folder.
    static func dynamicMeasured(home: String, excluding: Set<String> = []) async -> [Measured] {
        let cachesPath = "\(home)/Library/Caches"
        let children = await PathSizer.childDirectorySizes(of: cachesPath, timeout: 20)
        return dynamicMeasured(children: children, cachesPath: cachesPath, excluding: excluding)
    }

    static func dynamicMeasured(
        children: [PathSizer.ChildSize],
        cachesPath: String,
        excluding: Set<String> = []
    ) -> [Measured] {
        children.compactMap { child in
            let folder = URL(fileURLWithPath: child.path).lastPathComponent
            guard !folder.hasPrefix("."),
                  !folder.hasPrefix("com.apple."),
                  !excluding.contains(child.path),
                  child.bytes >= minimumBytes else {
                return nil
            }

            return Measured(
                target: Target(
                    name: cacheDisplayName(for: folder),
                    path: child.path,
                    risk: .caution,
                    relatedApps: relatedApps(forCacheFolder: folder)
                ),
                bytes: child.bytes
            )
        }
    }

    static func cacheDisplayName(for folder: String) -> String {
        switch folder {
        case "com.microsoft.VSCode.ShipIt": return "VSCode update"
        case "Google": return "Google Chrome"
        case "com.spotify.client": return "Spotify"
        case "copilot": return "Copilot"
        default: return folder
        }
    }

    static func relatedApps(forCacheFolder folder: String) -> [String] {
        switch folder {
        case "com.microsoft.VSCode.ShipIt": return ["code"]
        case "Google": return ["google chrome"]
        case "com.spotify.client": return ["spotify"]
        default: return []
        }
    }

    /// `~/Library/Caches` contains the Homebrew cache. When both are measured,
    /// the parent must not count the child's bytes a second time.
    static func removingNestedOverlap(_ measured: [Measured]) -> [Measured] {
        measured.compactMap { item in
            let nestedBytes = measured
                .filter {
                    $0.target.path != item.target.path
                        && $0.target.path.hasPrefix(item.target.path + "/")
                }
                .reduce(Int64(0)) { $0 + $1.bytes }

            let bytes = max(0, item.bytes - nestedBytes)
            guard bytes >= minimumBytes else { return nil }
            return Measured(target: item.target, bytes: bytes)
        }
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
        case "code": return "VS Code"
        case "google chrome": return "Google Chrome"
        case "spotify": return "Spotify"
        default:
            return String(process.prefix(1)).uppercased() + String(process.dropFirst())
        }
    }
}
