import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var page = ReviewPageModel()
    @StateObject private var filter = ReviewFilterModel()
    @StateObject private var actions = ReviewActionModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $actions.isConfirming) {
            ActionConfirmationView(
                items: actions.pending,
                isRunning: actions.isRunning,
                onCancel: { actions.cancelConfirmation() },
                onConfirm: { confirmActions() }
            )
        }
        .onChange(of: page.category) { _ in
            actions.clear()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $page.selection) {
                Label("Overview", systemImage: "square.grid.2x2")
                    .badge(badge(allItems.count))
                    .tag(ReviewPage.overview)
                    .contentShape(Rectangle())
                    .onTapGesture { page.selection = .overview }

                Section("Review") {
                    ForEach(Self.reviewOrder, id: \.rawValue) { category in
                        Label(category.title, systemImage: category.symbol)
                            .badge(badge(count(of: category)))
                            .tag(ReviewPage.category(category))
                            .contentShape(Rectangle())
                            .onTapGesture { page.selection = .category(category) }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)

                Text("Read-only by default")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Startup and process cleanup are the product's job, so they lead. Memory
    /// and disk stay available as context, not as the first thing to read.
    private static let reviewOrder: [ItemCategory] = [
        .startup, .processes, .services, .caches, .leftovers, .memory, .disk
    ]

    private func badge(_ count: Int) -> Text? {
        count > 0 ? Text("\(count)") : nil
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
                .padding(.horizontal, 24)

            if appState.report != nil {
                statStrip
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }

            if !actions.reports.isEmpty {
                resultCard
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            if appState.report != nil {
                filterRow
                    .padding(.horizontal, 24)

                content
                    .padding(.horizontal, 24)

                actionBar
            } else {
                emptyState
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
            value: actions.reports.count
        )
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 12) {
                Text(pageTitle)
                    .font(.largeTitle.weight(.semibold))

                Spacer(minLength: 12)

                Button {
                    Task { await appState.analyze() }
                } label: {
                    Label(appState.isScanning ? "Analyzing…" : "Analyze", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isScanning)
            }

            Text(pageDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.isScanning || appState.errorMessage != nil {
                HStack(spacing: 5) {
                    if appState.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Text(appState.errorMessage ?? appState.status)
                        .font(.caption)
                        .foregroundStyle(appState.errorMessage == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                .padding(.top, 1)
            }
        }
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            SearchField(text: $filter.searchText, placeholder: "Search")
                .frame(width: 240, height: 22)

            Picker("Risk", selection: $filter.risk) {
                Text("All risks").tag(Risk?.none)

                ForEach(Risk.allCases, id: \.rawValue) { risk in
                    Text("\(risk.label) (\(count(of: risk)))").tag(Risk?.some(risk))
                }
            }
            .labelsHidden()
            .frame(width: 135)

            Menu("Select") {
                Button("None") { actions.clear() }
                Button("All Changeable") { actions.selectAll(filteredItems) }
                Button("Needs Review") { actions.selectNeedingReview(filteredItems) }
            }
            .frame(width: 80)

            Spacer(minLength: 0)

            if filter.isActive {
                Button("Reset") { filter.reset() }
                    .buttonStyle(.link)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let report = appState.report {
            let items = visibleItems(in: report)

            if items.isEmpty {
                noResultsState
            } else {
                itemList(items)
            }
        } else {
            emptyState
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
    }

    private func itemList(_ items: [ScanItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                rows(sortedForReview(items))
            }
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func rows(_ items: [ScanItem]) -> some View {
        let showsCategory = page.category == nil

        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            ItemRow(
                item: item,
                isSelected: actions.isSelected(item),
                canSelect: item.canBeChanged,
                showsCategory: showsCategory,
                onToggle: { actions.toggle(item) }
            )

            if index < items.count - 1 {
                Hairline()
                    .padding(.leading, showsCategory ? 130 : 108)
            }
        }
    }

    private func sortedForReview(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted { lhs, rhs in
            if lhs.risk.sortRank != rhs.risk.sortRank {
                return lhs.risk.sortRank < rhs.risk.sortRank
            }

            let left = lhs.impactBytes ?? -1
            let right = rhs.impactBytes ?? -1
            if left != right { return left > right }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if let report = appState.report {
            let items = visibleItems(in: report)
            let changeable = items.filter(\.canBeChanged)
            let selected = items.filter { actions.isSelected($0) }

            if !changeable.isEmpty {
                HStack(spacing: 12) {
                    if actions.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(selected.isEmpty
                         ? "\(changeable.count) \(changeable.count == 1 ? "item" : "items") can be changed"
                         : "\(selected.count) of \(changeable.count) selected")
                        .font(.callout)
                        .foregroundStyle(selected.isEmpty ? Color.secondary : Color.primary)

                    Spacer(minLength: 8)

                    if !selected.isEmpty {
                        Button("Deselect") { actions.clear() }
                            .buttonStyle(.link)

                        Button(ActionExecutor.title(for: selected)) {
                            actions.beginConfirmation(with: selected)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(actions.isRunning)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .overlay(alignment: .top) { Hairline() }
            }
        }
    }

    // MARK: - Stats

    private var statStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1, height: 32)
                        .padding(.horizontal, 14)
                }

                StatBlock(stat: stat)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
    }

    private var stats: [Stat] {
        guard let report = appState.report else { return [] }

        let dangerous = report.items.filter { $0.risk == .dangerous }.count
        let caution = report.items.filter { $0.risk == .caution }.count
        let review = dangerous + caution
        let reclaimable = report.items
            .filter(\.canBeChanged)
            .compactMap(\.impactBytes)
            .reduce(0, +)

        let reviewTint: Color = dangerous > 0 ? .red : (caution > 0 ? .orange : .green)
        let memoryTint: Color
        switch report.memory.pressure {
        case .critical: memoryTint = .red
        case .warning: memoryTint = .orange
        case .normal: memoryTint = .primary
        }

        let usedRatio = Double(report.disk.usedBytes) / Double(max(report.disk.totalBytes, 1))
        let diskTint: Color = usedRatio >= 0.90 ? .red : (usedRatio >= 0.80 ? .orange : .primary)

        let swap: String = report.memory.swapUsedBytes > 0
            ? " · swap \(formatMemory(report.memory.swapUsedBytes))"
            : " · no swap"

        return [
            Stat(
                value: "\(report.items.count)",
                label: "Findings",
                tint: .primary,
                help: "\(report.items.count) items found in this scan."
            ),
            Stat(
                value: "\(review)",
                label: "Need review",
                tint: reviewTint,
                help: "\(dangerous) dangerous · \(caution) caution"
            ),
            Stat(
                value: format(reclaimable),
                label: "Reclaimable",
                tint: reclaimable > 0 ? .green : .secondary,
                help: "Space and memory the changeable items can release."
            ),
            Stat(
                value: formatMemory(report.memory.usedBytes),
                label: "Memory used",
                tint: memoryTint,
                help: "\(formatMemory(report.memory.usedBytes)) of \(formatMemory(report.memory.totalBytes)) used\(swap)"
            ),
            Stat(
                value: format(report.disk.freeBytes),
                label: "Disk free",
                tint: diskTint,
                help: "\(format(report.disk.freeBytes)) free · \(Int(usedRatio * 100))% used"
            )
        ]
    }

    // MARK: - Result

    private var resultCard: some View {
        let tint: Color = actions.failedCount > 0 ? .orange : .green
        let symbol = actions.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"

        let headline: String
        if actions.failedCount > 0 {
            headline = "\(actions.changedCount) of \(actions.reports.count) completed"
        } else if actions.reclaimedBytes > 0 {
            headline = "\(format(actions.reclaimedBytes)) freed"
        } else {
            headline = "\(actions.changedCount) \(actions.changedCount == 1 ? "item" : "items") changed"
        }

        return HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                Text("\(actions.changedCount) succeeded · \(actions.failedCount) failed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Dismiss") { actions.dismissSummary() }
                .buttonStyle(.link)
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No items match")
                .font(.callout.weight(.medium))

            Text("Try a different search or clear the filters.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Reset filters") { filter.reset() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No scan yet")
                .font(.title3.weight(.semibold))

            Text("Run Analyze to inspect memory, processes, startup items, services, disk, caches and leftovers. Nothing is modified.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy

    private var pageTitle: String {
        guard let category = page.category else { return "Overview" }

        switch category {
        case .memory: return "Memory"
        case .processes: return "Processes"
        case .startup: return "Startup & Login"
        case .services: return "Services"
        case .disk: return "Disk"
        case .caches: return "Caches"
        case .leftovers: return "Leftovers"
        }
    }

    private var pageDescription: String {
        guard let category = page.category else {
            return "Everything SiftBar found. Nothing changes until you choose it."
        }

        switch category {
        case .memory: return "How the system is using memory right now."
        case .processes: return "Heavy processes running now. Quit what you do not need."
        case .startup: return "Apps and agents that start automatically. Disable what you do not recognize."
        case .services: return "Homebrew services that start or run in the background."
        case .disk: return "Space used on the startup volume."
        case .caches: return "Recreatable data. Moving it to the Trash slows the next run but keeps your files."
        case .leftovers: return "Application Support folders with no matching app. Review before deleting."
        }
    }

    // MARK: - Data

    private var allItems: [ScanItem] {
        appState.report?.items ?? []
    }

    private var filteredItems: [ScanItem] {
        filter.apply(to: categoryItems(page.category, in: allItems))
    }

    private func visibleItems(in report: ScanReport) -> [ScanItem] {
        filter.apply(to: categoryItems(page.category, in: report.items))
    }

    private func categoryItems(_ category: ItemCategory?, in items: [ScanItem]) -> [ScanItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }

    private func count(of category: ItemCategory) -> Int {
        allItems.filter { $0.category == category }.count
    }

    private func count(of risk: Risk) -> Int {
        // The risk picker must show counts for every risk, so ignore the
        // currently selected risk while computing them.
        var base = filter.current
        base.risk = nil

        return base
            .apply(to: categoryItems(page.category, in: allItems))
            .filter { $0.risk == risk }
            .count
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func confirmActions() {
        Task {
            await actions.run()
            await appState.analyze()
        }
    }
}

private struct Stat {
    let value: String
    let label: String
    let tint: Color
    let help: String
}

private struct StatBlock: View {
    let stat: Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stat.value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(stat.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(stat.help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.label): \(stat.value). \(stat.help)")
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }
}

/// Native search field: gives the standard magnifier, clear button, focus ring
/// and Escape behavior that a styled `TextField` only imitates.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text

        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
