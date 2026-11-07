import AppKit
import Combine
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var page = ReviewPageModel()
    @StateObject private var filter = ReviewFilterModel()
    @StateObject private var actions = ReviewActionModel()
    @StateObject private var expanded = ExpansionModel()
    @StateObject private var history = HistoryPanelModel()
    @StateObject private var searchFocus = SearchFocusModel()
    @AppStorage("SiftBar.diskMapExpanded") private var diskMapExpanded = false
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
        .background {
            VStack {
                Button("") { Task { await appState.analyze() } }
                    .keyboardShortcut("r", modifiers: .command)

                Button("") { history.show() }
                    .keyboardShortcut("y", modifiers: .command)

                Button("") { searchFocus.focus() }
                    .keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $actions.isConfirming) {
            ActionConfirmationView(
                items: actions.pending,
                isRunning: actions.isRunning,
                onCancel: { actions.cancelConfirmation() },
                onConfirm: { confirmActions() }
            )
        }
        .sheet(isPresented: $history.isPresented) {
            HistoryView(records: history.records) {
                history.isPresented = false
            }
        }
        .sheet(isPresented: $appState.isAccessSheetPresented) {
            AccessOnboardingView(state: appState)
        }
        .onAppear {
            appState.presentAccessSheetIfNeeded()
        }
        .onChange(of: page.category) { _ in
            actions.clear()
            expanded.clear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftBarShowHistory)) { _ in
            history.show()
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftBarFocusSearch)) { _ in
            searchFocus.focus()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $page.selection) {
                Label("Overview", systemImage: "square.grid.2x2")
                    .badge(badge(allMetrics.findings))
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

            if let report = appState.report, page.category == .memory {
                memoryCard(report)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            if let report = appState.report, page.category == .disk {
                diskCard(report)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
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
                    history.show()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .help("Show action history (⌘Y)")

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

            if appState.isScanning || appState.errorMessage != nil || appState.lastDuration != nil {
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
            SearchField(text: $filter.searchText, placeholder: "Search", focusToken: searchFocus.token)
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
                Button("All Changeable") { actions.selectAll(flattened(filteredItems)) }
                Button("Needs Review") { actions.selectNeedingReview(flattened(filteredItems)) }
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
            } else if page.category == .disk, items.contains(where: { $0.canBeChanged }) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Clean up")
                            .font(.headline)

                        Spacer(minLength: 8)

                        Text("Select changeable items; large files can be reviewed in Finder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)

                    itemList(items)
                }
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
        let showsCategory = page.category == nil || page.category == .disk
        let display = displayRows(items)

        ForEach(Array(display.enumerated()), id: \.element.id) { index, row in
            ItemRow(
                item: row.item,
                isSelected: actions.isSelected(row.item),
                canSelect: row.item.canBeChanged,
                showsCategory: showsCategory && !row.isChild,
                isChild: row.isChild,
                hasChildren: !row.item.children.isEmpty,
                isExpanded: expanded.contains(row.item.id),
                onToggleExpanded: { expanded.toggle(row.item.id) },
                onToggle: { actions.toggle(row.item) },
                quickActionTitle: quickActionTitle(for: row.item, isChild: row.isChild),
                onQuickAction: { performQuickAction(for: row.item, isChild: row.isChild) }
            )

            if index < display.count - 1 {
                Hairline()
                    .padding(.leading, row.isChild ? 148 : (showsCategory ? 144 : 122))
            }
        }
    }

    private func displayRows(_ items: [ScanItem]) -> [DisplayRow] {
        items.flatMap { item -> [DisplayRow] in
            var rows = [DisplayRow(item: item, isChild: false)]

            if expanded.contains(item.id) {
                rows.append(contentsOf: item.children.map { DisplayRow(item: $0, isChild: true) })
            }

            return rows
        }
    }

    private func flattened(_ items: [ScanItem]) -> [ScanItem] {
        items.flatMap { item in
            guard expanded.contains(item.id) else { return [item] }
            return [item] + item.children
        }
    }

    private func quickActionTitle(for item: ScanItem, isChild: Bool) -> String? {
        guard !isChild else { return nil }
        if item.isProtected { return "Activity Monitor" }
        if item.category == .disk && item.risk != .safe { return "Review caches" }
        if item.category == .memory && item.risk != .safe { return "Open Processes" }
        guard item.canBeChanged else { return nil }

        switch item.action {
        case .killProcess:
            return "Quit"
        case .trashLeftover:
            return "Review"
        default:
            return nil
        }
    }

    private func performQuickAction(for item: ScanItem, isChild: Bool) {
        guard !isChild else { return }

        if item.isProtected {
            ActivityMonitor.open()
        } else if item.category == .disk && item.risk != .safe {
            page.selection = .category(.caches)
        } else if item.category == .memory && item.risk != .safe {
            page.selection = .category(.processes)
        } else {
            actions.beginConfirmation(with: [item])
        }
    }

    private func sortedForReview(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted { lhs, rhs in
            if lhs.isProtected != rhs.isProtected {
                return !lhs.isProtected
            }

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
            let items = flattened(visibleItems(in: report))
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

    // MARK: - Domain cards

    private static let breakdownColors: [Color] = [
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemTeal),
        Color(nsColor: .systemPink),
        Color(nsColor: .systemIndigo),
        Color(nsColor: .systemYellow),
        Color(nsColor: .systemGray)
    ]

    private func memoryCard(_ report: ScanReport) -> some View {
        let memory = report.memory
        let used = memory.hasBreakdown
            ? min(memory.appBytes + memory.wiredBytes + memory.compressedBytes, memory.totalBytes)
            : memory.usedBytes
        let remaining = memory.totalBytes > used ? memory.totalBytes - used : 0
        let free = min(memory.freeBytes, remaining)
        let other = remaining - free

        var segments: [BreakdownSegment] = []
        if memory.hasBreakdown {
            segments = [
                BreakdownSegment(name: "App", bytes: Int64(memory.appBytes), color: Self.breakdownColors[0], memoryUnits: true),
                BreakdownSegment(name: "Wired", bytes: Int64(memory.wiredBytes), color: Self.breakdownColors[1], memoryUnits: true),
                BreakdownSegment(name: "Compressed", bytes: Int64(memory.compressedBytes), color: Self.breakdownColors[2], memoryUnits: true),
                BreakdownSegment(name: "Cached & other", bytes: Int64(other), color: Self.breakdownColors[7], memoryUnits: true)
            ]
        } else {
            segments = [
                BreakdownSegment(name: "Used", bytes: Int64(used), color: Self.breakdownColors[0], memoryUnits: true)
            ]
        }
        segments.append(BreakdownSegment(
            name: "Free",
            bytes: Int64(free),
            color: Color(nsColor: .systemGreen).opacity(0.65),
            memoryUnits: true
        ))

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Memory breakdown")
                    .font(.headline)

                Spacer(minLength: 8)

                Text(memory.pressure.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(memoryTint(memory))

                Text("\(formatMemory(memory.totalBytes)) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if memory.swapUsedBytes > 0 {
                    Text("· swap \(formatMemory(memory.swapUsedBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            BreakdownBar(segments: segments, total: Int64(memory.totalBytes))

            HStack(spacing: 14) {
                ForEach(segments) { segment in
                    BreakdownLegend(segment: segment)
                }

                Spacer(minLength: 0)
            }

            if !memory.hasBreakdown {
                Text("Detailed memory counters were unavailable in this scan. Run Analyze again to refresh them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func diskCard(_ report: ScanReport) -> some View {
        let disk = report.disk
        let free = max(0, disk.totalBytes - disk.usedBytes)
        let usedColor: Color
        if disk.usedRatio >= 0.90 {
            usedColor = .red
        } else if disk.usedRatio >= 0.80 {
            usedColor = .orange
        } else {
            usedColor = Self.breakdownColors[0]
        }
        let segments = [
            BreakdownSegment(name: "Used", bytes: disk.usedBytes, color: usedColor),
            BreakdownSegment(name: "Available", bytes: free, color: Color(nsColor: .systemGreen).opacity(0.65))
        ]
        let breakdown = report.items
            .filter(\.isBreakdown)
            .sorted { ($0.impactBytes ?? 0) > ($1.impactBytes ?? 0) }
        let metrics = ReviewMetrics.make(visible: [], all: report.items)

        return VStack(alignment: .leading, spacing: 10) {
            if !appState.includesProtectedFolders {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)

                    Text("Partial disk map — Desktop, Documents and Downloads are not measured.")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button("Complete access") {
                        appState.presentAccessSheet()
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .padding(8)
                .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Where space goes")
                    .font(.headline)

                Spacer(minLength: 8)

                Text("\(format(disk.usedBytes)) used of \(format(disk.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if disk.purgeableBytes > 0 {
                    Text("· \(format(disk.purgeableBytes)) purgeable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    diskMapExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(diskMapExpanded ? "Hide details" : "Show details")
                        Image(systemName: diskMapExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(diskMapExpanded
                      ? "Hide the space map and APFS volumes"
                      : "Show the space map and APFS volumes")
            }

            BreakdownBar(segments: segments, total: disk.totalBytes)

            HStack(spacing: 14) {
                BreakdownLegend(segment: segments[0])
                BreakdownLegend(segment: segments[1])
                Spacer(minLength: 0)
                if metrics.diskReclaimableBytes > 0 {
                    Text("SiftBar can move \(format(metrics.diskReclaimableBytes)) to the Trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if diskMapExpanded {
                if !breakdown.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(Array(breakdown.prefix(8).enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Self.breakdownColors[index % Self.breakdownColors.count])
                                    .frame(width: 6, height: 6)

                                Text(item.title)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text(item.impactLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .help(item.detail)
                        }
                    }

                    Text("Measured with du. System & other is the remainder that SiftBar does not scan. Protected folders may stay there until Full Disk Access is granted.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !disk.volumes.isEmpty {
                    Divider()
                        .padding(.vertical, 1)

                    HStack(alignment: .firstTextBaseline) {
                        Text("APFS volumes")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Text("System overhead is part of Used and cannot be cleaned by SiftBar.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 18),
                            GridItem(.flexible(), spacing: 18),
                            GridItem(.flexible(), spacing: 18)
                        ],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(Array(disk.volumes.enumerated()), id: \.element.id) { index, volume in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Self.breakdownColors[index % Self.breakdownColors.count])
                                    .frame(width: 6, height: 6)

                                Text(volume.name)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text(format(volume.bytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .help("APFS volume \(volume.id) · roles: \(volume.roles.joined(separator: ", "))")
                        }
                    }

                    Text("Volume totals can differ slightly from Used because APFS shares blocks and counts purgeable space separately.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: diskMapExpanded)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Stats

    private var stats: [Stat] {
        guard let report = appState.report else { return [] }
        let metrics = ReviewMetrics.make(
            visible: categoryItems(page.category, in: report.items),
            all: report.items
        )

        guard let category = page.category else {
            return overviewStats(report, metrics)
        }

        switch category {
        case .disk:
            return diskStats(report, metrics)
        case .memory:
            return memoryStats(report, metrics)
        case .caches:
            return reclaimStats(metrics)
        case .leftovers:
            return leftoverStats(metrics)
        case .processes:
            return processStats(metrics)
        case .startup, .services:
            return reviewStats(metrics)
        }
    }

    private func overviewStats(_ report: ScanReport, _ metrics: ReviewMetrics) -> [Stat] {
        [
            Stat(
                value: "\(metrics.findings)",
                label: "Findings",
                tint: .primary,
                help: "\(metrics.findings) actionable findings. \(metrics.informational) informational rows are not counted."
            ),
            Stat(
                value: "\(metrics.needReview)",
                label: "Need review",
                tint: reviewTint(metrics),
                help: "\(metrics.dangerous) dangerous · \(metrics.caution) caution"
            ),
            Stat(
                value: format(metrics.diskReclaimableBytes),
                label: "Disk reclaimable",
                tint: metrics.diskReclaimableBytes > 0 ? .green : .secondary,
                help: "Caches and reviewed leftovers that can be moved to the Trash. Memory is not included."
            ),
            Stat(
                value: formatMemory(UInt64(max(metrics.memoryReleasableBytes, 0))),
                label: "RAM if quit",
                tint: metrics.memoryReleasableBytes > 0 ? .primary : .secondary,
                help: "Memory that quitting the listed apps would release. This does not free disk space."
            ),
            Stat(
                value: format(report.disk.importantFreeBytes),
                label: "Disk available",
                tint: diskTint(report.disk),
                help: "\(format(report.disk.importantFreeBytes)) available, matching System Settings · \(Int(report.disk.usedRatio * 100))% used"
            )
        ]
    }

    private func diskStats(_ report: ScanReport, _ metrics: ReviewMetrics) -> [Stat] {
        [
            Stat(
                value: format(report.disk.usedBytes),
                label: "Used",
                tint: diskTint(report.disk),
                help: "Container-level used space. The Data volume alone uses \(format(report.disk.dataVolumeUsedBytes))."
            ),
            Stat(
                value: format(report.disk.importantFreeBytes),
                label: "Available",
                tint: .primary,
                help: "Includes \(format(report.disk.purgeableBytes)) of purgeable space, so it matches System Settings."
            ),
            Stat(
                value: format(metrics.cacheReclaimableBytes),
                label: "Caches",
                tint: metrics.cacheReclaimableBytes > 0 ? .green : .secondary,
                help: "Recreatable cache data SiftBar can move to the Trash. Empty the Trash to free it."
            ),
            Stat(
                value: format(metrics.diskReclaimableBytes),
                label: "Reclaimable",
                tint: metrics.diskReclaimableBytes > 0 ? .green : .secondary,
                help: "Caches plus reviewed leftovers. Leftovers are app data and need your confirmation."
            ),
            Stat(
                value: format(report.disk.purgeableBytes),
                label: "Purgeable",
                tint: .secondary,
                help: "Space macOS can free on demand. SiftBar does not delete purgeable data."
            )
        ]
    }

    private func memoryStats(_ report: ScanReport, _ metrics: ReviewMetrics) -> [Stat] {
        let memory = report.memory
        let tint = memoryTint(memory)
        let swap = memory.swapUsedBytes > 0 ? formatMemory(memory.swapUsedBytes) : "None"

        return [
            Stat(
                value: formatMemory(memory.usedBytes),
                label: "Used",
                tint: tint,
                help: "App + wired + compressed, the same definition Activity Monitor uses. \(formatMemory(memory.totalBytes)) total."
            ),
            Stat(
                value: memory.hasBreakdown ? formatMemory(memory.appBytes) : "—",
                label: "App memory",
                tint: .primary,
                help: "Memory used by apps and processes, excluding compressed and wired memory."
            ),
            Stat(
                value: memory.hasBreakdown ? formatMemory(memory.wiredBytes) : "—",
                label: "Wired",
                tint: .secondary,
                help: "Memory the system cannot page out."
            ),
            Stat(
                value: memory.hasBreakdown ? formatMemory(memory.compressedBytes) : "—",
                label: "Compressed",
                tint: memory.compressedBytes > 1_500_000_000 ? .orange : .secondary,
                help: "Memory macOS compressed instead of writing it to swap."
            ),
            Stat(
                value: swap,
                label: "Swap",
                tint: memory.swapUsedBytes > 2_000_000_000 ? .orange : .secondary,
                help: "Disk space being used as RAM. \(metrics.memoryReleasableBytes > 0 ? "Quitting listed apps can release \(formatMemory(UInt64(metrics.memoryReleasableBytes)))." : "")"
            )
        ]
    }

    private func reclaimStats(_ metrics: ReviewMetrics) -> [Stat] {
        let cacheBytes = categoryItems(.caches, in: allItems)
            .compactMap(\.impactBytes)
            .reduce(0, +)

        return [
            Stat(
                value: "\(metrics.findings)",
                label: "Items",
                tint: .primary,
                help: "Changeable cache items in this category."
            ),
            Stat(
                value: format(cacheBytes),
                label: "Caches",
                tint: cacheBytes > 0 ? .green : .secondary,
                help: "Recreatable cache data. Empty the Trash after moving it to actually free the space."
            ),
            Stat(
                value: "\(metrics.needReview)",
                label: "Need review",
                tint: reviewTint(metrics),
                help: "\(metrics.dangerous) dangerous · \(metrics.caution) caution"
            )
        ]
    }

    private func leftoverStats(_ metrics: ReviewMetrics) -> [Stat] {
        let items = categoryItems(.leftovers, in: allItems)
        let bytes = items.compactMap(\.impactBytes).reduce(0, +)

        return [
            Stat(
                value: "\(items.count)",
                label: "Possible leftovers",
                tint: items.isEmpty ? .secondary : .orange,
                help: "Application Support folders with no matching installed app."
            ),
            Stat(
                value: format(bytes),
                label: "Total size",
                tint: .primary,
                help: "App data that could be moved to the Trash. Review the contents first."
            ),
            Stat(
                value: "\(metrics.needReview)",
                label: "Need review",
                tint: reviewTint(metrics),
                help: "Leftovers are user data, not recreatable cache."
            )
        ]
    }

    private func processStats(_ metrics: ReviewMetrics) -> [Stat] {
        [
            Stat(
                value: "\(metrics.findings)",
                label: "Apps to review",
                tint: .primary,
                help: "Apps with processes above 150 MB that SiftBar can act on. Protected system processes are shown separately and are not counted."
            ),
            Stat(
                value: "\(metrics.needReview)",
                label: "Need review",
                tint: reviewTint(metrics),
                help: "\(metrics.caution) caution · \(metrics.dangerous) protected"
            ),
            Stat(
                value: formatMemory(UInt64(max(metrics.memoryReleasableBytes, 0))),
                label: "RAM if quit",
                tint: metrics.memoryReleasableBytes > 0 ? .primary : .secondary,
                help: "Sum of resident memory for the listed apps."
            )
        ]
    }

    private func reviewStats(_ metrics: ReviewMetrics) -> [Stat] {
        [
            Stat(
                value: "\(metrics.findings)",
                label: "Findings",
                tint: .primary,
                help: "Informational summary rows are not counted."
            ),
            Stat(
                value: "\(metrics.needReview)",
                label: "Need review",
                tint: reviewTint(metrics),
                help: "\(metrics.dangerous) dangerous · \(metrics.caution) caution"
            )
        ]
    }

    private func reviewTint(_ metrics: ReviewMetrics) -> Color {
        metrics.dangerous > 0 ? .red : (metrics.caution > 0 ? .orange : .green)
    }

    private func diskTint(_ disk: DiskStats) -> Color {
        if disk.usedRatio >= 0.90 { return .red }
        if disk.usedRatio >= 0.80 { return .orange }
        return .primary
    }

    private func memoryTint(_ memory: MemoryStats) -> Color {
        switch memory.pressure {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .primary
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        let tint: Color = actions.failedCount > 0 ? .orange : .green
        let symbol = actions.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"

        let headline: String
        if actions.failedCount > 0 {
            headline = "\(actions.changedCount) of \(actions.reports.count) completed"
        } else if actions.diskMovedBytes > 0 && actions.memoryReleasedBytes > 0 {
            headline = "\(format(actions.diskMovedBytes)) moved to Trash · \(formatMemory(UInt64(actions.memoryReleasedBytes))) RAM released"
        } else if actions.diskMovedBytes > 0 {
            headline = "\(format(actions.diskMovedBytes)) moved to Trash"
        } else if actions.memoryReleasedBytes > 0 {
            headline = "\(formatMemory(UInt64(actions.memoryReleasedBytes))) RAM released"
        } else {
            headline = "\(actions.changedCount) \(actions.changedCount == 1 ? "item" : "items") changed"
        }

        let detail: String
        if actions.diskMovedBytes > 0 {
            detail = "\(actions.changedCount) succeeded · \(actions.failedCount) failed · Empty the Trash to free space"
        } else {
            detail = "\(actions.changedCount) succeeded · \(actions.failedCount) failed"
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

                Text(detail)
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
        case .memory: return "What is using RAM and what quitting an app would release. This does not free disk space."
        case .processes: return "Heavy processes running now, grouped by app. Quit what you do not need."
        case .startup: return "Apps and agents that start automatically. Disable what you do not recognize."
        case .services: return "Homebrew services that start or run in the background."
        case .disk: return "Where space goes, what is safe to reclaim, and what SiftBar will not touch."
        case .caches: return "Recreatable data. Moving it to the Trash slows the next run but keeps your files."
        case .leftovers: return "App data left behind by apps that are no longer installed. Review before deleting."
        }
    }

    // MARK: - Data

    private var allItems: [ScanItem] {
        appState.report?.items ?? []
    }

    private var allMetrics: ReviewMetrics {
        ReviewMetrics.make(visible: allItems, all: allItems)
    }

    private var filteredItems: [ScanItem] {
        listItems(filter.apply(to: categoryItems(page.category, in: allItems)))
    }

    private func visibleItems(in report: ScanReport) -> [ScanItem] {
        listItems(filter.apply(to: categoryItems(page.category, in: report.items)))
    }

    /// Rows that belong in the scrollable list. Space-map rows live in the card,
    /// and the Disk tab uses the card for the startup-disk numbers instead of
    /// repeating them as a non-actionable row.
    private func listItems(_ items: [ScanItem]) -> [ScanItem] {
        items
            .filter { !$0.isBreakdown }
            .filter { !(page.category == .disk && $0.title == "Startup disk") }
    }

    private func categoryItems(_ category: ItemCategory?, in items: [ScanItem]) -> [ScanItem] {
        guard let category else { return items }
        if category == .memory {
            return items.filter { $0.category == .memory || $0.category == .processes }
        }
        if category == .disk {
            return items.filter {
                $0.category == .disk || $0.category == .caches || $0.category == .leftovers
            }
        }
        return items.filter { $0.category == category }
    }

    private func count(of category: ItemCategory) -> Int {
        categoryItems(category, in: allItems)
            .filter { !$0.isBreakdown && !$0.isInformational }
            .count
    }

    private func count(of risk: Risk) -> Int {
        // The risk picker must show counts for every risk, so ignore the
        // currently selected risk while computing them.
        var base = filter.current
        base.risk = nil

        return base
            .apply(to: categoryItems(page.category, in: allItems).filter { !$0.isBreakdown })
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

private struct BreakdownSegment: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let color: Color
    let memoryUnits: Bool

    init(name: String, bytes: Int64, color: Color, memoryUnits: Bool = false) {
        self.name = name
        self.bytes = bytes
        self.color = color
        self.memoryUnits = memoryUnits
    }

    var label: String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: memoryUnits ? .memory : .file
        )
    }
}

private struct BreakdownBar: View {
    let segments: [BreakdownSegment]
    let total: Int64

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(segments.filter { $0.bytes > 0 }) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(for: segment, in: geometry.size.width))
                }
            }
        }
        .frame(height: 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.name) \($0.label)" }.joined(separator: ", "))
    }

    private func width(for segment: BreakdownSegment, in available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(0, available * CGFloat(segment.bytes) / CGFloat(total))
    }
}

private struct BreakdownLegend: View {
    let segment: BreakdownSegment

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(segment.color)
                .frame(width: 7, height: 7)

            Text(segment.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(segment.label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

private struct DisplayRow: Identifiable {
    let item: ScanItem
    let isChild: Bool

    var id: UUID { item.id }
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
    let focusToken: Int

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        context.coordinator.lastFocusToken = focusToken
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text

        if field.stringValue != text {
            field.stringValue = text
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken

            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var lastFocusToken = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
