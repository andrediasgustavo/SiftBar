import Foundation

enum Risk: String, Codable, CaseIterable, Hashable, Sendable {
    case safe
    case caution
    case dangerous

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Caution"
        case .dangerous: return "Dangerous"
        }
    }
}

enum ItemCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case memory
    case processes
    case startup
    case services
    case disk
    case caches
    case leftovers

    var title: String {
        switch self {
        case .memory: return "Memory"
        case .processes: return "Processes"
        case .startup: return "Startup"
        case .services: return "Services"
        case .disk: return "Disk"
        case .caches: return "Caches"
        case .leftovers: return "Leftovers"
        }
    }

    var symbol: String {
        switch self {
        case .memory: return "memorychip"
        case .processes: return "cpu"
        case .startup: return "power"
        case .services: return "server.rack"
        case .disk: return "internaldrive"
        case .caches: return "archivebox"
        case .leftovers: return "questionmark.folder"
        }
    }

    var sortOrder: Int {
        switch self {
        case .memory: return 0
        case .processes: return 1
        case .startup: return 2
        case .services: return 3
        case .disk: return 4
        case .caches: return 5
        case .leftovers: return 6
        }
    }
}

enum ItemAction: Sendable, Equatable {
    case none
    case killProcess(pid: Int32, name: String)
    case disableLaunchItem(label: String)
    case enableLaunchItem(label: String)
    case stopService(name: String)
    case deletePath(path: String, bytes: Int64)
    /// Application Support data left behind by an app that is no longer
    /// installed. This is user data, not a cache, so it has its own action and
    /// a stricter confirmation path.
    case trashLeftover(path: String, bytes: Int64)

    /// Filesystem location a successful action removes. Used to prune every
    /// category view showing the same path even when a rescan mints new IDs.
    var targetPath: String? {
        switch self {
        case .deletePath(let path, _), .trashLeftover(let path, _):
            return path
        case .none, .killProcess, .disableLaunchItem,
            .enableLaunchItem, .stopService:
            return nil
        }
    }
}

struct ScanItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let category: ItemCategory
    let title: String
    let detail: String
    let impactLabel: String
    let impactBytes: Int64?
    let risk: Risk
    let action: ItemAction
    let evidence: String
    /// Extra warning shown in the row and in the confirmation sheet, e.g. an
    /// app that is still running while its cache is selected for removal.
    let warning: String?
    /// Rows that explain the system rather than describe something to change.
    /// They stay visible but never count as findings, review items, or
    /// reclaimable space.
    let isInformational: Bool
    /// A protected macOS process. It is shown for context, but SiftBar will
    /// never terminate it, so it must not look like an actionable danger.
    let isProtected: Bool
    /// A measured space-map row. Informational, and rendered as a chart/legend
    /// instead of a triage row.
    let isBreakdown: Bool
    /// Row produced by a slow `du` walk (space map, large consumers). Quick
    /// refreshes skip these collectors and reuse the previous report's rows.
    let isSlowRefresh: Bool
    /// Per-process rows for grouped processes. Empty for every other item.
    let children: [ScanItem]

    init(
        id: UUID = UUID(),
        category: ItemCategory,
        title: String,
        detail: String,
        impactLabel: String,
        impactBytes: Int64?,
        risk: Risk,
        action: ItemAction,
        evidence: String,
        warning: String? = nil,
        isInformational: Bool = false,
        isProtected: Bool = false,
        isBreakdown: Bool = false,
        isSlowRefresh: Bool = false,
        children: [ScanItem] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.impactLabel = impactLabel
        self.impactBytes = impactBytes
        self.risk = risk
        self.action = action
        self.evidence = evidence
        self.warning = warning
        self.isInformational = isInformational
        self.isProtected = isProtected
        self.isBreakdown = isBreakdown
        self.isSlowRefresh = isSlowRefresh
        self.children = children
    }

    /// Dangerous items are informational only; even if a collector attaches an
    /// action by mistake, the review UI must never offer to apply it.
    var isActionable: Bool {
        risk != .dangerous && action != .none
    }

    /// Which resource an action actually releases. Disk bytes and RAM must
    /// never be added together in a single "reclaimable" number.
    var reclaimDomain: ReclaimDomain? {
        switch action {
        case .deletePath, .trashLeftover:
            return .disk
        case .killProcess:
            return .memory
        case .none, .disableLaunchItem, .enableLaunchItem, .stopService:
            return nil
        }
    }
}

enum ReclaimDomain: String, Sendable {
    case disk
    case memory
}

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

protocol Collector: Sendable {
    var category: ItemCategory { get }
    func collect() async -> [ScanItem]
}
