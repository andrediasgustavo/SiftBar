import Foundation

struct CacheCollector: Collector {
    let category: ItemCategory = .caches

    private struct Target: Sendable {
        let name: String
        let path: String
        let risk: Risk
    }

    private struct Measured: Sendable {
        let target: Target
        let bytes: Int64
    }

    private let minimumBytes: Int64 = 20 * 1024 * 1024

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let targets: [Target] = [
            Target(name: "npm", path: "\(home)/.npm/_cacache", risk: .safe),
            Target(name: "Expo", path: "\(home)/.expo", risk: .safe),
            Target(name: "Xcode DerivedData", path: "\(home)/Library/Developer/Xcode/DerivedData", risk: .safe),
            Target(name: "Gradle", path: "\(home)/.gradle/caches", risk: .safe),
            Target(name: "Homebrew", path: "\(home)/Library/Caches/Homebrew", risk: .safe),
            Target(name: "CoreSimulator (user)", path: "\(home)/Library/Developer/CoreSimulator/Caches", risk: .safe),
            Target(name: "CoreSimulator (system)", path: "/Library/Developer/CoreSimulator/Caches", risk: .caution),
            Target(name: "General", path: "\(home)/Library/Caches", risk: .caution)
        ]

        var measured: [Measured] = []

        await withTaskGroup(of: Measured?.self) { group in
            for target in targets {
                group.addTask {
                    guard let bytes = await PathSizer.sizeInBytes(of: target.path),
                          bytes >= minimumBytes else { return nil }
                    return Measured(target: target, bytes: bytes)
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
                    evidence: "du -sk \(item.target.path)"
                )
            }
    }
}
