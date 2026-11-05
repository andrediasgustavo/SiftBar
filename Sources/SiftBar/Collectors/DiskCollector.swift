import Foundation

struct DiskCollector: Collector {
    let category: ItemCategory = .disk
    private let disk: DiskStats

    init(disk: DiskStats) {
        self.disk = disk
    }

    func collect() async -> [ScanItem] {
        guard disk.totalBytes > 0 else { return [] }

        let usedRatio = Double(disk.usedBytes) / Double(disk.totalBytes)
        let risk: Risk
        if usedRatio >= 0.90 {
            risk = .dangerous
        } else if usedRatio >= 0.80 {
            risk = .caution
        } else {
            risk = .safe
        }

        return [ScanItem(
            category: .disk,
            title: "Startup disk",
            detail: "\(formatted(disk.usedBytes)) used of \(formatted(disk.totalBytes)). Free space is reported by APFS and includes purgeable space.",
            impactLabel: "\(formatted(disk.freeBytes)) free",
            impactBytes: disk.freeBytes,
            risk: risk,
            action: .none,
            evidence: "df -k /System/Volumes/Data"
        )]
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
