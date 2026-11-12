import Foundation

/// A collector produces the rows for one area of the report (memory,
/// processes, caches, …). Collectors are read-only: actions never run here.
protocol Collector: Sendable {
    var category: ItemCategory { get }
    func collect() async -> [ScanItem]
}
