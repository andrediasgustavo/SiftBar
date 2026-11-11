import Foundation

/// Progress of an interactive scan. Drives the full-screen scan workspace
/// (no previous report) and the banner shown over existing results.
struct ScanProgress: Sendable, Equatable {
    /// 1 system snapshot, 2 memory/processes, 3 caches/leftovers, 4 disk map.
    let step: Int
    let doneSteps: Set<Int>
    /// 0...1, weighted across the four steps.
    let fraction: Double
    let message: String
    let startedAt: Date

    init(
        step: Int,
        doneSteps: Set<Int> = [],
        fraction: Double,
        message: String,
        startedAt: Date = Date()
    ) {
        self.step = min(max(step, 1), 4)
        self.doneSteps = doneSteps
        self.fraction = min(max(fraction, 0), 1)
        self.message = message
        self.startedAt = startedAt
    }

    static func title(for step: Int) -> String {
        switch step {
        case 1: return "System snapshot"
        case 2: return "Memory and processes"
        case 3: return "Caches and leftovers"
        default: return "Disk space map"
        }
    }

    var stepTitle: String {
        Self.title(for: step)
    }
}
