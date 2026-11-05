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

        let sorted = items.sorted { lhs, rhs in
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

        return ScanReport(
            generatedAt: Date(),
            items: sorted,
            memory: snapshot.memory,
            disk: snapshot.disk
        )
    }
}
