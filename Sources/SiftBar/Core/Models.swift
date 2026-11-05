import Foundation

enum Risk: String, Codable, CaseIterable, Sendable {
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

enum ItemCategory: String, Codable, CaseIterable, Sendable {
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
    case removeLoginItem(name: String)
    case disableLaunchItem(label: String)
    case stopService(name: String)
    case deletePath(path: String, bytes: Int64)
}

struct ScanItem: Identifiable, Sendable {
    let id: UUID
    let category: ItemCategory
    let title: String
    let detail: String
    let impactLabel: String
    let impactBytes: Int64?
    let risk: Risk
    let action: ItemAction
    let evidence: String

    init(
        id: UUID = UUID(),
        category: ItemCategory,
        title: String,
        detail: String,
        impactLabel: String,
        impactBytes: Int64?,
        risk: Risk,
        action: ItemAction,
        evidence: String
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
    }
}

struct MemoryStats: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let swapUsedBytes: UInt64
    let pressure: MemoryPressure
}

enum MemoryPressure: String, Sendable {
    case normal
    case warning
    case critical
}

struct DiskStats: Sendable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
}

struct SystemSnapshot: Sendable {
    let memory: MemoryStats
    let disk: DiskStats

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
}

protocol Collector: Sendable {
    var category: ItemCategory { get }
    func collect() async -> [ScanItem]
}
