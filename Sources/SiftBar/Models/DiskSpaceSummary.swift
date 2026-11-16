import Foundation

/// Presentation model for the Disk page. The collectors keep measuring many
/// technical categories; this turns them into four groups a non-technical
/// person can scan: apps, files, app data, and macOS.
struct DiskSpaceSummary: Equatable {
    enum Kind: String, CaseIterable, Equatable {
        case apps
        case files
        case appData
        case system
    }

    struct Part: Identifiable, Equatable {
        let title: String
        let bytes: Int64

        var id: String { title }
    }

    struct Group: Identifiable, Equatable {
        let kind: Kind
        let title: String
        let detail: String
        let bytes: Int64
        /// False only for "Your files" when the app has no access to the
        /// personal folders. The row still appears, with a way to add access.
        let isMeasured: Bool
        let parts: [Part]

        var id: String { kind.rawValue }
    }

    let groups: [Group]
    /// The denominator for the bar. It is never smaller than the groups, so a
    /// probe quirk cannot draw a bar wider than its container.
    let usedBytes: Int64
    let freeBytes: Int64
    let totalBytes: Int64

    static let empty = DiskSpaceSummary(
        groups: [],
        usedBytes: 0,
        freeBytes: 0,
        totalBytes: 0
    )

    static func make(
        items: [ScanItem],
        disk: DiskStats,
        includesProtectedFolders: Bool
    ) -> DiskSpaceSummary {
        let breakdown = items.filter(\.isBreakdown)
        var partsByKind: [Kind: [Part]] = [:]
        var rawBytes: Int64 = 0

        for item in breakdown {
            guard let kind = kind(for: item.title) else { continue }
            let bytes = item.impactBytes ?? 0
            rawBytes += bytes
            guard bytes > 0 else { continue }

            partsByKind[kind, default: []].append(
                Part(title: friendlyPartTitle(item.title), bytes: bytes)
            )
        }

        // Small categories are omitted from the map, and a failed probe can
        // leave a gap. Keep the reconciliation honest by showing the
        // difference inside the macOS group instead of hiding it.
        let unexplained = max(0, disk.usedBytes - rawBytes)
        if unexplained > 0 {
            partsByKind[.system, default: []].append(
                Part(title: "Other system data", bytes: unexplained)
            )
        }

        var groups: [Group] = []

        for kind in Kind.allCases {
            let parts = (partsByKind[kind] ?? []).sorted { $0.bytes > $1.bytes }
            let bytes = parts.reduce(Int64(0)) { $0 + $1.bytes }

            if kind == .files && !includesProtectedFolders {
                groups.append(Group(
                    kind: .files,
                    title: "Your files",
                    detail: "Documents, Desktop, Downloads and iCloud Drive are not measured without access.",
                    bytes: 0,
                    isMeasured: false,
                    parts: []
                ))
                continue
            }

            guard bytes > 0 else { continue }
            groups.append(Group(
                kind: kind,
                title: title(for: kind),
                detail: detail(for: kind),
                bytes: bytes,
                isMeasured: true,
                parts: parts
            ))
        }

        let measured = groups.filter(\.isMeasured).reduce(Int64(0)) { $0 + $1.bytes }
        let used = max(disk.usedBytes, measured)

        return DiskSpaceSummary(
            groups: groups,
            usedBytes: used,
            freeBytes: disk.importantFreeBytes,
            totalBytes: disk.totalBytes
        )
    }

    /// The collector and the demo still use their technical names. Keeping the
    /// mapping here means the rest of the app (and the tests) keep working.
    static func kind(for title: String) -> Kind? {
        switch title {
        case "Applications", "Developer":
            return .apps
        case "Documents & media", "Other user folders", "iCloud Drive":
            return .files
        case "App data", "Caches":
            return .appData
        case "System-wide data", "System & other":
            return .system
        default:
            return nil
        }
    }

    static func title(for kind: Kind) -> String {
        switch kind {
        case .apps: return "Apps and tools"
        case .files: return "Your files"
        case .appData: return "App data and caches"
        case .system: return "macOS and protected"
        }
    }

    static func detail(for kind: Kind) -> String {
        switch kind {
        case .apps:
            return "Applications and the developer tools installed on this Mac."
        case .files:
            return "Documents, Desktop, Downloads, other folders and iCloud Drive."
        case .appData:
            return "Settings, support files and caches. Caches can be recreated."
        case .system:
            return "macOS, system files and data it protects. SiftBar won't touch these."
        }
    }

    static func friendlyPartTitle(_ title: String) -> String {
        switch title {
        case "Applications": return "Applications"
        case "Developer": return "Developer tools"
        case "Documents & media": return "Documents, Desktop and Downloads"
        case "Other user folders": return "Other folders"
        case "iCloud Drive": return "iCloud Drive"
        case "App data": return "App data"
        case "Caches": return "Caches"
        case "System-wide data": return "System files"
        case "System & other": return "macOS and protected files"
        default: return title
        }
    }
}
