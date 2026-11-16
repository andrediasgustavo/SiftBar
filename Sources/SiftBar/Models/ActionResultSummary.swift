import Foundation

/// Pure copy for the post-action result card. Keeping it out of the view lets
/// the "freed vs moved to Trash vs RAM" rules be tested without launching UI.
struct ActionResultSummary: Equatable {
    let headline: String
    let detail: String
    let showsTrashButton: Bool

    static func make(
        changedCount: Int,
        failedCount: Int,
        reportCount: Int,
        freedBytes: Int64,
        movedBytes: Int64,
        memoryBytes: Int64,
        formatDisk: (Int64) -> String,
        formatMemory: (Int64) -> String
    ) -> ActionResultSummary {
        let headline: String

        if failedCount > 0 {
            headline = changedCount == 0
                ? "\(failedCount) \(failedCount == 1 ? "item" : "items") failed"
                : "\(changedCount) of \(reportCount) succeeded"
        } else {
            var outcomes: [String] = []
            if freedBytes > 0 {
                outcomes.append("\(formatDisk(freedBytes)) freed")
            }
            if movedBytes > 0 {
                outcomes.append("\(formatDisk(movedBytes)) moved to Trash")
            }
            if memoryBytes > 0 {
                outcomes.append("\(formatMemory(memoryBytes)) RAM released")
            }
            headline = outcomes.isEmpty
                ? "\(changedCount) \(changedCount == 1 ? "item" : "items") changed"
                : outcomes.joined(separator: " · ")
        }

        let detail: String
        if movedBytes > 0 {
            detail = "\(changedCount) succeeded · \(failedCount) failed · Empty the Trash to free space"
        } else if freedBytes > 0 {
            detail = "\(changedCount) succeeded · \(failedCount) failed · Space freed immediately"
        } else {
            detail = "\(changedCount) succeeded · \(failedCount) failed"
        }

        return ActionResultSummary(
            headline: headline,
            detail: detail,
            showsTrashButton: movedBytes > 0
        )
    }
}
