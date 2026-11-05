import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            metrics
            analysisPanel

            if let report = appState.report {
                reviewHeader(report)
                itemList(report)
            } else {
                emptyState
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 560)
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

    private func reviewHeader(_ report: ScanReport) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Review")
                .font(.headline)

            Text("Read-only results")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(report.generatedAt.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func itemList(_ report: ScanReport) -> some View {
        List {
            ForEach(sections(from: report)) { section in
                Section {
                    ForEach(section.items) { item in
                        ItemRow(item: item)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    }
                } header: {
                    Label(
                        "\(section.category.title) · \(section.items.count)",
                        systemImage: section.category.symbol
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func sections(from report: ScanReport) -> [CategorySection] {
        ItemCategory.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { category -> CategorySection? in
                let items = report.items.filter { $0.category == category }
                guard !items.isEmpty else { return nil }
                return CategorySection(category: category, items: items)
            }
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
