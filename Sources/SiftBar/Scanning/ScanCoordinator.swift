import Foundation

enum ScanCoordinator {
    static func run(
        includeProtectedFolders: Bool = true,
        includeSlowCollectors: Bool = true,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanReport {
        let state = ProgressState(progress: progress)

        state.report(step: 1, fraction: 0.02, message: "Reading system information")
        let snapshot = await SystemProbe.snapshotOrEmpty()

        if Task.isCancelled {
            state.finish()
            return ScanReport(
                generatedAt: Date(),
                items: [],
                memory: snapshot.memory,
                disk: snapshot.disk
            )
        }

        state.markDone(step: 1)
        state.report(
            step: 2,
            fraction: 0.10,
            message: "Reading memory, processes and startup items"
        )

        // Fast system state first: process and startup scans should not compete
        // with the large `du` walks for I/O or the process table. Each
        // collector is tagged with the workspace step it belongs to so the
        // checklist can complete in real time.
        let fastPlan: [PlannedCollector] = [
            PlannedCollector(step: 2, collector: MemoryCollector(memory: snapshot.memory)),
            PlannedCollector(step: 2, collector: ProcessCollector()),
            PlannedCollector(step: 2, collector: StartupCollector()),
            PlannedCollector(step: 2, collector: BrewCollector()),
            PlannedCollector(step: 2, collector: DiskCollector(disk: snapshot.disk)),
            PlannedCollector(step: 3, collector: CacheCollector()),
            PlannedCollector(step: 3, collector: OrphanCollector())
        ]

        var items = await collect(fastPlan) { completed, total, finishedSteps in
            state.markDone(steps: finishedSteps)
            let fraction = 0.10 + 0.45 * Double(completed) / Double(max(total, 1))
            state.report(
                step: state.currentStep(upTo: 3),
                fraction: fraction,
                message: ProgressState.message(for: state.currentStep(upTo: 3))
            )
        }

        // The space map and large-consumer walks hit big folders with `du`.
        // They run after the fast collectors so a busy disk cannot make the
        // process list time out, and they can be skipped entirely for the
        // quick refresh used after action batches.
        if includeSlowCollectors, !Task.isCancelled {
            state.report(
                step: 4,
                fraction: 0.56,
                message: "Mapping disk usage — this is the slow part"
            )

            let slowPlan: [PlannedCollector] = [
                PlannedCollector(
                    step: 4,
                    collector: LargeConsumersCollector(
                        includeProtectedFolders: includeProtectedFolders
                    )
                ),
                PlannedCollector(
                    step: 4,
                    collector: DiskUsageCollector(
                        disk: snapshot.disk,
                        includeProtectedFolders: includeProtectedFolders
                    )
                )
            ]

            items.append(contentsOf: await collect(slowPlan) { completed, total, finishedSteps in
                state.markDone(steps: finishedSteps)
                let fraction = 0.56 + 0.39 * Double(completed) / Double(max(total, 1))
                state.report(
                    step: 4,
                    fraction: fraction,
                    message: "Mapping disk usage — this is the slow part"
                )
            })
        }

        state.finish()

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

    // MARK: - Collection with progress

    private struct PlannedCollector {
        let step: Int
        let collector: any Collector
    }

    private static func collect(
        _ plan: [PlannedCollector],
        onProgress: ((Int, Int, Set<Int>) -> Void)? = nil
    ) async -> [ScanItem] {
        var totals: [Int: Int] = [:]
        for entry in plan {
            totals[entry.step, default: 0] += 1
        }

        var finished: [Int: Int] = [:]

        return await withTaskGroup(of: (Int, [ScanItem]).self) { group in
            for entry in plan {
                group.addTask {
                    (entry.step, await entry.collector.collect())
                }
            }

            var all: [ScanItem] = []
            var completed = 0

            for await (step, batch) in group {
                all.append(contentsOf: batch)
                completed += 1
                finished[step, default: 0] += 1

                let doneSteps = Set(totals.compactMap { candidate, total in
                    (finished[candidate] ?? 0) >= total ? candidate : nil
                })

                onProgress?(completed, plan.count, doneSteps)
            }

            return all
        }
    }

    /// Mutable progress snapshot shared by the coordinator. All mutations
    /// happen on the coordinator task (the `for await` loop), never inside a
    /// child task, so the unchecked sendability is safe here.
    private final class ProgressState: @unchecked Sendable {
        private let progress: (@Sendable (ScanProgress) -> Void)?
        private let startedAt = Date()
        private var doneSteps: Set<Int> = []

        init(progress: (@Sendable (ScanProgress) -> Void)?) {
            self.progress = progress
        }

        func markDone(step: Int) {
            doneSteps.insert(step)
        }

        func markDone(steps: Set<Int>) {
            doneSteps.formUnion(steps)
        }

        /// First step in `1...maxStep` that is not complete. Steps 2 and 3 run
        /// in parallel; the checklist simply completes as their collectors do.
        func currentStep(upTo maxStep: Int) -> Int {
            for step in 1...maxStep where !doneSteps.contains(step) {
                return step
            }
            return maxStep
        }

        func report(step: Int, fraction: Double, message: String) {
            progress?(ScanProgress(
                step: step,
                doneSteps: doneSteps,
                fraction: fraction,
                message: message,
                startedAt: startedAt
            ))
        }

        func finish() {
            markDone(steps: [1, 2, 3, 4])
            report(step: 4, fraction: 1, message: "Done")
        }

        static func message(for step: Int) -> String {
            switch step {
            case 1: return "Reading system information"
            case 2: return "Reading memory, processes and startup items"
            case 3: return "Measuring caches and leftovers"
            default: return "Mapping disk usage — this is the slow part"
            }
        }
    }
}
