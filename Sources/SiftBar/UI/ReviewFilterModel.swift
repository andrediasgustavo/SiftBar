import SwiftUI

/// Observable wrapper around `ReviewFilter` so the dashboard can bind to it.
/// `@State` is a macro in recent SwiftUI SDKs; using `@StateObject` keeps the
/// direct-`swiftc` build working with Command Line Tools only.
final class ReviewFilterModel: ObservableObject {
    @Published var category: ItemCategory?
    @Published var risk: Risk?
    @Published var searchText: String = ""

    var isActive: Bool {
        current.isActive
    }

    var current: ReviewFilter {
        var filter = ReviewFilter()
        filter.category = category
        filter.risk = risk
        filter.searchText = searchText
        return filter
    }

    func apply(to items: [ScanItem]) -> [ScanItem] {
        current.apply(to: items)
    }

    func reset() {
        category = nil
        risk = nil
        searchText = ""
    }
}
