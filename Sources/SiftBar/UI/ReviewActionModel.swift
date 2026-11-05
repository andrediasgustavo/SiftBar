import Foundation
import SwiftUI

/// Selection and execution state for a review page.
@MainActor
final class ReviewActionModel: ObservableObject {
    @Published private(set) var selected = Set<UUID>()
    @Published var isConfirming = false
    @Published private(set) var isRunning = false
    @Published private(set) var reports: [ActionReport] = []
    @Published private(set) var pending: [ScanItem] = []

    func isSelected(_ item: ScanItem) -> Bool {
        selected.contains(item.id)
    }

    func toggle(_ item: ScanItem) {
        guard item.canBeChanged else { return }

        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
    }

    func clear() {
        selected.removeAll()
    }

    func selectAll(_ items: [ScanItem]) {
        selected = Set(items.filter(\.canBeChanged).map(\.id))
    }

    func selectNeedingReview(_ items: [ScanItem]) {
        selected = Set(
            items
                .filter(\.canBeChanged)
                .filter { $0.risk != .safe }
                .map(\.id)
        )
    }

    func selectedItems(in items: [ScanItem]) -> [ScanItem] {
        items.filter { selected.contains($0.id) }
    }

    func beginConfirmation(with items: [ScanItem]) {
        guard !items.isEmpty else { return }
        pending = items
        isConfirming = true
    }

    func cancelConfirmation() {
        isConfirming = false
        pending = []
    }

    func run() async {
        guard !isRunning, !pending.isEmpty else { return }

        isRunning = true
        isConfirming = false

        var results: [ActionReport] = []
        for item in pending {
            results.append(await ActionExecutor.perform(item))
        }

        reports = results
        isRunning = false
        selected.removeAll()
        pending = []
    }

    var changedCount: Int {
        reports.filter(\.success).count
    }

    var failedCount: Int {
        reports.filter { !$0.success }.count
    }

    var reclaimedBytes: Int64 {
        reports.filter(\.success).reduce(0) { $0 + $1.reclaimedBytes }
    }

    var allSucceeded: Bool {
        !reports.isEmpty && reports.allSatisfy(\.success)
    }

    func dismissSummary() {
        reports = []
    }
}

/// A page in the review sidebar. Non-optional so `List` selection matches the
/// row tags reliably on macOS.
enum ReviewPage: Hashable {
    case overview
    case category(ItemCategory)
}

final class ReviewPageModel: ObservableObject {
    @Published var selection: ReviewPage = .overview

    var category: ItemCategory? {
        if case .category(let category) = selection { return category }
        return nil
    }
}
