import Foundation

/// Filters the review list by category, risk, and free-text search.
struct ReviewFilter: Equatable {
    var category: ItemCategory?
    var risk: Risk?
    /// Restricts the leftovers list to one confidence level. `nil` keeps every
    /// confidence visible.
    var confidence: LeftoverConfidence?
    var searchText: String = ""

    var isActive: Bool {
        category != nil || risk != nil || confidence != nil || !normalizedSearchText.isEmpty
    }

    mutating func reset() {
        category = nil
        risk = nil
        confidence = nil
        searchText = ""
    }

    func apply(to items: [ScanItem]) -> [ScanItem] {
        let terms = searchTerms

        return items.filter { item in
            if let category, item.category != category { return false }
            if let risk, item.risk != risk { return false }
            if let confidence, item.category == .leftovers,
               item.leftoverConfidence != confidence { return false }
            guard !terms.isEmpty else { return true }

            let haystack = Self.searchableText(for: item)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// Search matches the title, detail, impact label, evidence, and category.
    static func searchableText(for item: ScanItem) -> String {
        normalize([
            item.title,
            item.detail,
            item.impactLabel,
            item.evidence,
            item.category.title
        ].joined(separator: " "))
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static func count(of category: ItemCategory, in items: [ScanItem]) -> Int {
        items.filter { $0.category == category }.count
    }

    static func count(of risk: Risk, in items: [ScanItem]) -> Int {
        items.filter { $0.risk == risk }.count
    }

    private var searchTerms: [String] {
        normalizedSearchText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var normalizedSearchText: String {
        Self.normalize(searchText).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
