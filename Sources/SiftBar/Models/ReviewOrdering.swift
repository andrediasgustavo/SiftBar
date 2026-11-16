import Foundation

/// Triage order shared by every review list.
///
/// Informational rows are context, even when their internal risk is caution
/// (large app data, simulator summaries). They go after every actionable Safe
/// row; mixing them into the caution/safe queue made the list read as noisy.
enum ReviewOrdering {
    static func sorted(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted { lhs, rhs in
            if lhs.isInformational != rhs.isInformational {
                return !lhs.isInformational
            }

            if lhs.isProtected != rhs.isProtected {
                return !lhs.isProtected
            }

            if lhs.risk.sortRank != rhs.risk.sortRank {
                return lhs.risk.sortRank < rhs.risk.sortRank
            }

            // Low-confidence leftovers stay at the bottom of their risk group:
            // they are context, not a finding to act on.
            let leftConfidence = lhs.leftoverConfidence?.sortRank ?? 0
            let rightConfidence = rhs.leftoverConfidence?.sortRank ?? 0
            if leftConfidence != rightConfidence {
                return leftConfidence < rightConfidence
            }

            let left = lhs.impactBytes ?? -1
            let right = rhs.impactBytes ?? -1
            if left != right { return left > right }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
