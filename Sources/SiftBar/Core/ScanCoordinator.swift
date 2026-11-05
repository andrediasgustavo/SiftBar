import Foundation

enum ScanCoordinator {
    static func run() async -> ScanReport {
        let snapshot = await SystemProbe.snapshotOrEmpty()

        let collectors: [any Collector] = [
            MemoryCollector(memory: snapshot.memory),
            ProcessCollector(),
            StartupCollector(),
            BrewCollector(),
            DiskCollector(disk: snapshot.disk),
            CacheCollector(),
            OrphanCollector()
        ]

        let items = await withTaskGroup(of: [ScanItem].self) { group in
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

        return ScanReport(
            generatedAt: Date(),
            items: sort(items),
            memory: snapshot.memory,
            disk: snapshot.disk
        )
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
