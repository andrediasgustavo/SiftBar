import Foundation

struct MemoryStats: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let swapUsedBytes: UInt64
    let pressure: MemoryPressure
    /// Breakdown as Activity Monitor presents it. Zero when the probe could
    /// not read the detailed counters.
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64

    init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        swapUsedBytes: UInt64,
        pressure: MemoryPressure,
        appBytes: UInt64 = 0,
        wiredBytes: UInt64 = 0,
        compressedBytes: UInt64 = 0,
        cachedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.freeBytes = freeBytes
    }

    var hasBreakdown: Bool {
        appBytes + wiredBytes + compressedBytes > 0
    }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(usedBytes) / Double(totalBytes), 1)
    }
}

enum MemoryPressure: String, Sendable {
    case normal
    case warning
    case critical

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

struct DiskStats: Sendable {
    /// Container size, matching the total shown by System Settings.
    let totalBytes: Int64
    /// Container-level used space: `total - availableForImportantUsage`.
    let usedBytes: Int64
    /// Strict free space from `df` (does not include purgeable space).
    let freeBytes: Int64
    /// The writable Data volume's own used space. Kept for evidence and for
    /// explaining why `df` alone does not match System Settings.
    let dataVolumeUsedBytes: Int64
    /// Space macOS can make available on demand, including purgeable data.
    let availableForImportantUsageBytes: Int64
    /// Difference between important-usage availability and strict `df` free.
    let purgeableBytes: Int64
    /// Volume-level usage from `diskutil apfs list -plist`. This explains the
    /// part of "Used" that is not a folder SiftBar can measure or clean.
    let volumes: [DiskVolume]

    init(
        totalBytes: Int64,
        usedBytes: Int64,
        freeBytes: Int64,
        dataVolumeUsedBytes: Int64 = 0,
        availableForImportantUsageBytes: Int64 = 0,
        purgeableBytes: Int64 = 0,
        volumes: [DiskVolume] = []
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.dataVolumeUsedBytes = dataVolumeUsedBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
        self.purgeableBytes = purgeableBytes
        self.volumes = volumes
    }

    /// The number to show next to "Available" so it matches System Settings.
    var importantFreeBytes: Int64 {
        availableForImportantUsageBytes > 0 ? availableForImportantUsageBytes : freeBytes
    }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var hasContainerBreakdown: Bool {
        dataVolumeUsedBytes > 0 || availableForImportantUsageBytes > 0
    }
}

struct DiskVolume: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let roles: [String]
    let bytes: Int64

    var isSystem: Bool {
        roles.contains("System")
    }
}

struct SystemSnapshot: Sendable {
    let memory: MemoryStats
    let disk: DiskStats

    /// Convenience accessors kept for tests and callers that only need totals.
    var totalMemoryBytes: UInt64 { memory.totalBytes }
    var freeDiskBytes: Int64 { disk.freeBytes }

    static let empty = SystemSnapshot(
        memory: MemoryStats(totalBytes: 0, usedBytes: 0, swapUsedBytes: 0, pressure: .normal),
        disk: DiskStats(totalBytes: 0, usedBytes: 0, freeBytes: 0)
    )
}

struct ScanReport: Sendable {
    let generatedAt: Date
    let items: [ScanItem]
    let memory: MemoryStats
    let disk: DiskStats

    /// A healthy Mac always reports memory and disk totals. Both zero means
    /// the probes failed outright (for example because the commands could not
    /// be launched) and the empty report should be presented as an error.
    var failedToReadSystem: Bool {
        memory.totalBytes == 0 && disk.totalBytes == 0
    }

    /// Drops succeeded items without waiting for the next full scan. The same
    /// item backs every category view (Disk shows caches + leftovers), so
    /// filtering by ID keeps all tabs consistent instantly. Children of grouped
    /// processes are pruned too when a child action succeeds. `paths` covers
    /// the case where a concurrent scan minted new IDs: matching filesystem
    /// paths are removed as well.
    func removingItems(withIDs ids: Set<UUID>, paths: Set<String> = []) -> ScanReport {
        guard !ids.isEmpty || !paths.isEmpty else { return self }

        func matches(_ item: ScanItem) -> Bool {
            if ids.contains(item.id) { return true }
            if let path = item.action.targetPath, paths.contains(path) { return true }
            return false
        }

        let pruned: [ScanItem] = items.compactMap { item in
            if matches(item) { return nil }
            guard !item.children.isEmpty else { return item }

            let kept = item.children.filter { !matches($0) }
            guard kept.count != item.children.count else { return item }

            return ScanItem(
                id: item.id,
                category: item.category,
                title: item.title,
                detail: item.detail,
                impactLabel: item.impactLabel,
                impactBytes: item.impactBytes,
                risk: item.risk,
                action: item.action,
                evidence: item.evidence,
                warning: item.warning,
                isInformational: item.isInformational,
                isProtected: item.isProtected,
                isBreakdown: item.isBreakdown,
                isSlowRefresh: item.isSlowRefresh,
                children: kept
            )
        }

        return ScanReport(
            generatedAt: generatedAt,
            items: pruned,
            memory: memory,
            disk: disk
        )
    }

    /// Combines a quick refresh (fast collectors only) with the previous
    /// report's slow rows, so the space map stays visible while a background
    /// pass recomputes it.
    func mergingSlowItems(from previous: ScanReport) -> ScanReport {
        let slow = previous.items.filter(\.isSlowRefresh)
        guard !slow.isEmpty else { return self }

        return ScanReport(
            generatedAt: generatedAt,
            items: ScanCoordinator.sort(items + slow),
            memory: memory,
            disk: disk
        )
    }
}
