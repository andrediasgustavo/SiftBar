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
