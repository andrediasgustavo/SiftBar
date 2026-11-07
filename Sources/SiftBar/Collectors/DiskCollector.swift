import Foundation

struct DiskCollector: Collector {
    let category: ItemCategory = .disk
    private let disk: DiskStats

    init(disk: DiskStats) {
        self.disk = disk
    }

    func collect() async -> [ScanItem] {
        Self.item(for: disk).map { [$0] } ?? []
    }

    static func item(for disk: DiskStats) -> ScanItem? {
        guard disk.totalBytes > 0 else { return nil }

        let risk = risk(forUsedRatio: disk.usedRatio)
        let purgeable = disk.purgeableBytes > 0
            ? " macOS can also reclaim \(format(disk.purgeableBytes)) of purgeable space on demand."
            : ""

        return ScanItem(
            category: .disk,
            title: "Startup disk",
            detail: "\(format(disk.usedBytes)) used of \(format(disk.totalBytes)). \(format(disk.importantFreeBytes)) available, matching System Settings.\(purgeable)",
            impactLabel: "\(format(disk.importantFreeBytes)) available",
            impactBytes: disk.importantFreeBytes,
            risk: risk,
            action: .none,
            evidence: "df -k /System/Volumes/Data + volumeAvailableCapacityForImportantUsage",
            isInformational: risk == .safe
        )
    }

    /// At 80% used the disk deserves attention; at 90% it is a real problem.
    static func risk(forUsedRatio ratio: Double) -> Risk {
        if ratio >= 0.90 { return .dangerous }
        if ratio >= 0.80 { return .caution }
        return .safe
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
