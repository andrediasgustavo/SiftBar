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
    @Published private(set) var failedItems: [ScanItem] = []
    @Published var showsFailureDetails = false

    private let history: HistoryStore

    init(history: HistoryStore = HistoryStore()) {
        self.history = history
    }

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

        let items = pending
        let startedAt = Date()

        var results: [ActionReport] = []
        for item in items {
            results.append(await ActionExecutor.perform(item))
        }

        let failedItems = zip(results, items).compactMap { report, item in
            report.success ? nil : item
        }

        let entries = zip(results, items).map { report, item in
            HistoryEntry(item: item, report: report)
        }
        history.append(HistoryRecord(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: Date(),
            entries: entries
        ))

        reports = results
        self.failedItems = failedItems
        isRunning = false
        selected.removeAll()
        pending = []
        showsFailureDetails = false
    }

    /// Opens the confirmation sheet again with only the items that failed, so
    /// a retry is still an explicit, reviewed action.
    func beginRetryOfFailures() {
        guard !isRunning, !failedItems.isEmpty else { return }
        pending = failedItems
        isConfirming = true
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

    var diskMovedBytes: Int64 {
        reports.filter { $0.success && $0.movedToTrash }.reduce(0) { $0 + $1.reclaimedBytes }
    }

    var memoryReleasedBytes: Int64 {
        reports.filter { $0.success && $0.domain == .memory }.reduce(0) { $0 + $1.reclaimedBytes }
    }

    var allSucceeded: Bool {
        !reports.isEmpty && reports.allSatisfy(\.success)
    }

    /// IDs that no longer exist on disk (moved to Trash, quit, disabled).
    /// `ActionReport.id` is the source `ScanItem.id`, so the dashboard can
    /// prune every category view that shows the same item.
    var succeededIDs: Set<UUID> {
        Set(reports.filter(\.success).map(\.id))
    }

    func dismissSummary() {
        reports = []
        failedItems = []
        showsFailureDetails = false
    }

    /// README/demo hook: show a realistic success card without touching disk.
    func loadDemoReports() {
        let caches = DemoReport.make().items.filter { $0.category == .caches }
        reports = caches.prefix(2).map { item in
            ActionReport(item: item, success: true, message: "Moved to Trash")
        }
        failedItems = []
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

/// Tracks which grouped-process rows are expanded.
final class ExpansionModel: ObservableObject {
    @Published private(set) var expanded = Set<UUID>()

    func contains(_ id: UUID) -> Bool {
        expanded.contains(id)
    }

    func toggle(_ id: UUID) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    func clear() {
        expanded.removeAll()
    }
}

/// Triggers focus in the search field when the menu's Find command runs.
final class SearchFocusModel: ObservableObject {
    @Published private(set) var token = 0

    func focus() {
        token += 1
    }
}

/// Loads the audit history for the history sheet.
@MainActor
final class HistoryPanelModel: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var records: [HistoryRecord] = []

    private let store: HistoryStore

    init(store: HistoryStore = HistoryStore()) {
        self.store = store
    }

    func show() {
        records = Array(store.load().reversed())
        isPresented = true
    }
}
