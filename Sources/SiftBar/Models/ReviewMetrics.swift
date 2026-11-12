import Foundation

/// Numbers shared by the dashboard, badges, and menu bar status.
///
/// Counts are scoped to the rows currently visible (a category or the whole
/// report). Reclaimable totals are always computed from the whole report and
/// split by resource, because disk bytes and RAM bytes are not additive.
struct ReviewMetrics: Equatable, Sendable {
    let findings: Int
    let needReview: Int
    let dangerous: Int
    let caution: Int
    let informational: Int
    let actionable: Int

    let diskReclaimableBytes: Int64
    let cacheReclaimableBytes: Int64
    let memoryReleasableBytes: Int64

    static let empty = ReviewMetrics(
        findings: 0,
        needReview: 0,
        dangerous: 0,
        caution: 0,
        informational: 0,
        actionable: 0,
        diskReclaimableBytes: 0,
        cacheReclaimableBytes: 0,
        memoryReleasableBytes: 0
    )

    static func make(visible: [ScanItem], all: [ScanItem]) -> ReviewMetrics {
        let visibleFindings = visible.filter { !$0.isInformational }
        let allReclaimable = all.filter { !$0.isInformational && $0.canBeChanged }
        let cacheReclaimable = allReclaimable.filter {
            if case .deletePath = $0.action { return true }
            return false
        }

        return ReviewMetrics(
            findings: visibleFindings.count,
            needReview: visibleFindings.filter { $0.risk != .safe }.count,
            dangerous: visibleFindings.filter { $0.risk == .dangerous }.count,
            caution: visibleFindings.filter { $0.risk == .caution }.count,
            informational: visible.filter(\.isInformational).count,
            actionable: visibleFindings.filter(\.isActionable).count,
            diskReclaimableBytes: sum(allReclaimable, domain: .disk),
            cacheReclaimableBytes: sum(cacheReclaimable, domain: .disk),
            memoryReleasableBytes: sum(allReclaimable, domain: .memory)
        )
    }

    private static func sum(_ items: [ScanItem], domain: ReclaimDomain) -> Int64 {
        items
            .filter { $0.reclaimDomain == domain }
            .compactMap(\.impactBytes)
            .reduce(0, +)
    }
}
