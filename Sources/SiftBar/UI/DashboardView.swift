import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var filter = ReviewFilterModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            metrics
            analysisPanel

            if let report = appState.report {
                filterBar(report)
                reviewHeader(report)

                if filteredItems.isEmpty {
                    noResultsState
                } else {
                    itemList(filteredItems)
                }
            } else {
                emptyState
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 560)
    }

    private var filteredItems: [ScanItem] {
        guard let report = appState.report else { return [] }
        return filter.apply(to: report.items)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("SiftBar")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            }

            Text("Analyze first. Change only what you choose.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "Memory",
                value: formattedMemoryUsed,
                subtitle: memorySubtitle
            )
            MetricCard(
                title: "Disk Free",
                value: formattedDiskFree,
                subtitle: diskSubtitle
            )
            MetricCard(
                title: "Items",
                value: appState.report.map { "\($0.items.count)" } ?? "—",
                subtitle: itemsSubtitle
            )
        }
    }

    private var analysisPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { await appState.analyze() }
                } label: {
                    Label(appState.isScanning ? "Analyzing..." : "Analyze", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isScanning)

                if appState.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if appState.report != nil {
                    Button("Clear") {
                        filter.reset()
                        appState.clearReport()
                    }
                    .buttonStyle(.link)
                }
            }

            Text(appState.errorMessage ?? appState.status)
                .font(.caption)
                .foregroundStyle(appState.errorMessage == nil ? Color.secondary : Color.red)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func filterBar(_ report: ScanReport) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Search items", text: $filter.searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)

                if !filter.searchText.isEmpty {
                    Button {
                        filter.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 220)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))

            Picker("Category", selection: $filter.category) {
                Text("All categories").tag(ItemCategory?.none)

                ForEach(ItemCategory.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.rawValue) { category in
                    let count = ReviewFilter.count(of: category, in: report.items)
                    if count > 0 {
                        Text("\(category.title) (\(count))").tag(ItemCategory?.some(category))
                    }
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Picker("Risk", selection: $filter.risk) {
                Text("All risks").tag(Risk?.none)

                ForEach(Risk.allCases, id: \.rawValue) { risk in
                    let count = ReviewFilter.count(of: risk, in: report.items)
                    if count > 0 {
                        Text("\(risk.label) (\(count))").tag(Risk?.some(risk))
                    }
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Spacer(minLength: 0)

            if filter.isActive {
                Button("Reset") {
                    filter.reset()
                }
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func reviewHeader(_ report: ScanReport) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Review")
                .font(.headline)

            Text(
                filter.isActive
                    ? "Showing \(filteredItems.count) of \(report.items.count)"
                    : "Read-only results"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Text(report.generatedAt.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func itemList(_ items: [ScanItem]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections(from: items)) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "\(section.category.title) · \(section.items.count)",
                            systemImage: section.category.symbol
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                        ForEach(section.items) { item in
                            ItemRow(item: item)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func sections(from items: [ScanItem]) -> [CategorySection] {
        ItemCategory.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { category -> CategorySection? in
                let categoryItems = items.filter { $0.category == category }
                guard !categoryItems.isEmpty else { return nil }
                return CategorySection(category: category, items: categoryItems)
            }
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No items match")
                .font(.callout.weight(.medium))

            Text("Try a different search or clear the filters.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Reset filters") {
                filter.reset()
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No scan yet")
                .font(.callout.weight(.medium))
            Text("Run Analyze to inspect memory, processes, startup items, services, disk, caches and leftovers. Nothing is modified.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("Read-only by default. Nothing is changed without confirmation.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var formattedMemoryUsed: String {
        guard let report = appState.report else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(report.memory.usedBytes), countStyle: .memory)
    }

    private var formattedDiskFree: String {
        guard let report = appState.report else { return "—" }
        return ByteCountFormatter.string(fromByteCount: report.disk.freeBytes, countStyle: .file)
    }

    private var memorySubtitle: String {
        guard let report = appState.report else { return "Physical RAM" }
        let total = ByteCountFormatter.string(fromByteCount: Int64(report.memory.totalBytes), countStyle: .memory)
        guard report.memory.swapUsedBytes > 0 else {
            return "of \(total) · no swap"
        }
        let swap = ByteCountFormatter.string(fromByteCount: Int64(report.memory.swapUsedBytes), countStyle: .memory)
        return "of \(total) · swap \(swap)"
    }

    private var diskSubtitle: String {
        guard let report = appState.report else { return "Startup volume" }
        let used = ByteCountFormatter.string(fromByteCount: report.disk.usedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: report.disk.totalBytes, countStyle: .file)
        return "\(used) used of \(total)"
    }

    private var itemsSubtitle: String {
        if appState.isScanning { return "Scanning..." }
        guard let duration = appState.lastDuration else { return "Not scanned" }
        return String(format: "in %.1f s", duration)
    }
}

private struct CategorySection: Identifiable {
    let category: ItemCategory
    let items: [ScanItem]

    var id: String { category.rawValue }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
}
