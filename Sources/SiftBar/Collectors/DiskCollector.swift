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

        let usedRatio = Double(disk.usedBytes) / Double(disk.totalBytes)

        return ScanItem(
            category: .disk,
            title: "Startup disk",
            detail: "\(format(disk.usedBytes)) used of \(format(disk.totalBytes)). Free space is reported by APFS and includes purgeable space.",
            impactLabel: "\(format(disk.freeBytes)) free",
            impactBytes: disk.freeBytes,
            risk: risk(forUsedRatio: usedRatio),
            action: .none,
            evidence: "df -k /System/Volumes/Data"
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
