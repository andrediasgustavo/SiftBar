import Foundation

enum ScanCoordinator {
    static func run(includeProtectedFolders: Bool = true) async -> ScanReport {
        let snapshot = await SystemProbe.snapshotOrEmpty()

        // Fast system state first: process and startup scans should not compete
        // with the large `du` walks for I/O or the process table.
        let fastCollectors: [any Collector] = [
            MemoryCollector(memory: snapshot.memory),
            ProcessCollector(),
            StartupCollector(),
            BrewCollector(),
            DiskCollector(disk: snapshot.disk),
            LargeConsumersCollector(includeProtectedFolders: includeProtectedFolders),
            CacheCollector(),
            OrphanCollector()
        ]

        var items = await collect(fastCollectors)

        // The space map walks ~/Library and /Library. Run it after the fast
        // collectors so a busy disk cannot make the process list time out.
        items.append(contentsOf: await collect([
            DiskUsageCollector(
                disk: snapshot.disk,
                includeProtectedFolders: includeProtectedFolders
            )
        ]))

        return ScanReport(
            generatedAt: Date(),
            items: sort(items),
            memory: snapshot.memory,
            disk: snapshot.disk
        )
    }

    private static func collect(_ collectors: [any Collector]) async -> [ScanItem] {
        await withTaskGroup(of: [ScanItem].self) { group in
            for collector in collectors {
                group.addTask {
                    await collector.collect()
                }
            }

            var all: [ScanItem] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }
    }

    /// Groups items by category order, then by impact (largest first), then
    /// alphabetically. Items without a byte impact sort after those with one.
    static func sort(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            let leftImpact = lhs.impactBytes ?? -1
            let rightImpact = rhs.impactBytes ?? -1
            if leftImpact != rightImpact {
                return leftImpact > rightImpact
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
