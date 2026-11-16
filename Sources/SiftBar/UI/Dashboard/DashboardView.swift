import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var page = ReviewPageModel()
    @StateObject private var filter = ReviewFilterModel()
    @StateObject private var actions = ReviewActionModel()
    @StateObject private var expanded = ExpansionModel()
    @StateObject private var history = HistoryPanelModel()
    @StateObject private var searchFocus = SearchFocusModel()
    /// Advanced disk information starts collapsed every time the page opens.
    /// It is intentionally not persisted: a previous deep dive should not make
    /// the next visit dense.
    @State private var showDiskDetails = false
    @State private var showTechnicalDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 900, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            VStack {
                Button("") { Task { await appState.analyze() } }
                    .keyboardShortcut("r", modifiers: .command)

                Button("") { history.show() }
                    .keyboardShortcut("y", modifiers: .command)

                Button("") { searchFocus.focus() }
                    .keyboardShortcut("f", modifiers: .command)

                Button("") { exportReport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(appState.report == nil)
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
        .sheet(isPresented: $appState.isAccessSheetPresented, onDismiss: {
            appState.accessSheetDidDismiss()
        }) {
            AccessOnboardingView(state: appState)
        }
        .onAppear {
            appState.presentAccessSheetIfNeeded()

            #if SIFTBAR_DEMO
            let arguments = CommandLine.arguments
            if arguments.contains("--demo-result") {
                actions.loadDemoReports()
            }
            if arguments.contains("--demo-refresh") {
                // Screenshot hook: simulates the post-action refresh so the
                // banner and the thin background line can be captured.
                Task {
                    await appState.refreshQuickly()
                    await appState.refreshInBackground()
                }
            }
            if arguments.contains("--demo-confirmation"),
               let item = appState.report?.items.first(where: {
                   $0.category == .caches && $0.canBeChanged
               }) {
                actions.beginConfirmation(with: [item])
            }

            // Documentation hooks: let the screenshot script open a specific
            // page without UI automation.
            if let index = arguments.firstIndex(of: "--demo-page"),
               index + 1 < arguments.count,
               let category = Self.demoCategory(named: arguments[index + 1]) {
                page.selection = .category(category)
            }
            if arguments.contains("--demo-details") || arguments.contains("--demo-system-other") {
                // The demo page change resets the disclosure in onChange; let
                // that settle before opening it for the screenshot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showDiskDetails = true
                }
            }
            #endif
        }
        .onChange(of: page.category) { _ in
            actions.clear()
            expanded.clear()
            showDiskDetails = false
            showTechnicalDetails = false
            // The confidence picker only exists on Leftovers. Do not carry its
            // value into another page where it would hide rows.
            filter.confidence = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftBarShowHistory)) { _ in
            history.show()
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftBarFocusSearch)) { _ in
            searchFocus.focus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftBarExportReport)) { _ in
            exportReport()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $page.selection) {
                Label("Overview", systemImage: "square.grid.2x2")
                    .font(.system(size: 14))
                    .badge(badge(allMetrics.findings))
                    .tag(ReviewPage.overview)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("sidebar.overview")
                    .onTapGesture { page.selection = .overview }

                ForEach(Self.sidebarSections) { section in
                    Section {
                        ForEach(section.categories, id: \.rawValue) { category in
                            categoryRow(category)
                        }
                    } header: {
                        Text(section.title)
                            .font(.system(size: 12.5, weight: .semibold))
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
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }

    private struct SidebarSection: Identifiable {
        let title: String
        let categories: [ItemCategory]

        var id: String { title }
    }

    /// Storage is the consolidated cleanup destination, so it sits apart from
    /// the review queue instead of being mixed into it. Memory is context.
    private static let sidebarSections: [SidebarSection] = [
        SidebarSection(title: "Review", categories: [.startup, .processes, .services]),
        SidebarSection(title: "Storage", categories: [.disk, .caches, .leftovers]),
        SidebarSection(title: "System", categories: [.memory])
    ]

    #if SIFTBAR_DEMO
    /// Demo/screenshot hook: maps `--demo-page <name>` to a sidebar page.
    private static func demoCategory(named name: String) -> ItemCategory? {
        switch name {
        case "startup": return .startup
        case "processes": return .processes
        case "services": return .services
        case "disk": return .disk
        case "caches": return .caches
        case "leftovers": return .leftovers
        case "memory": return .memory
        default: return nil
        }
    }
    #endif

    private func categoryRow(_ category: ItemCategory) -> some View {
        Label(category.title, systemImage: category.symbol)
            .font(.system(size: 14))
            .badge(badge(count(of: category)))
            .tag(ReviewPage.category(category))
            .contentShape(Rectangle())
            .accessibilityIdentifier("sidebar.\(category.rawValue)")
            .onTapGesture { page.selection = .category(category) }
    }

    private func badge(_ count: Int) -> Text? {
        count > 0 ? Text("\(count)") : nil
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
                .padding(.horizontal, 24)

            if appState.scanPresentation == .workspace {
                ScanWorkspaceView(
                    progress: appState.scanProgress,
                    onStop: { appState.cancelScan() }
                )
            } else {
                if appState.scanPresentation == .slim {
                    ScanProgressLine(progress: appState.scanProgress)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                if appState.report != nil {
                    statStrip
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                }

                if appState.scanPresentation == .banner {
                    ScanProgressBanner(
                        progress: appState.scanProgress,
                        onStop: { appState.cancelScan() }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                if appState.report != nil {
                    // One page scroll keeps the header fixed and lets the map
                    // grow when "Show details" is opened, instead of pushing
                    // the title and toolbar out of the window.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
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

                            filterRow
                                .padding(.horizontal, 24)

                            content
                                .padding(.horizontal, 24)
                                .opacity(appState.scanPresentation == .banner ? 0.45 : 1)
                                .allowsHitTesting(appState.scanPresentation != .banner)
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("page.scroll")

                    actionBar
                } else {
                    firstRunView
                        .padding(.horizontal, 24)
                }
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
                    .font(.system(size: 24, weight: .semibold))

                Spacer(minLength: 12)

                if appState.report != nil {
                    Button {
                        exportReport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .help("Export the current report as Markdown (⌘E)")
                    .accessibilityIdentifier("header.export")
                }

                Button {
                    history.show()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .help("Show action history (⌘Y)")
                .accessibilityIdentifier("header.history")

                // The first-run screen owns the only primary action while no
                // report exists; showing both would duplicate the button.
                if DashboardPresentation.showsHeaderAnalyze(report: appState.report) {
                    Button {
                        Task { await appState.analyze() }
                    } label: {
                        Label(analyzeLabel, systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || appState.isScanning)
                    .accessibilityIdentifier("header.analyze")
                }
            }

            Text(pageDescription)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let showsHeaderStatus = appState.errorMessage != nil
                || appState.scanPresentation == .slim
                || (appState.scanPresentation == .none
                    && (appState.isScanning || appState.lastDuration != nil))

            if showsHeaderStatus {
                HStack(spacing: 5) {
                    if appState.isScanning && appState.scanPresentation == .none {
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
            .accessibilityIdentifier("filter.risk")

            if page.category == .leftovers {
                Picker("Confidence", selection: $filter.confidence) {
                    Text("All confidence").tag(LeftoverConfidence?.none)

                    ForEach(LeftoverConfidence.allCases, id: \.rawValue) { confidence in
                        Text("\(confidence.shortLabel) (\(confidenceCount(confidence)))")
                            .tag(LeftoverConfidence?.some(confidence))
                    }
                }
                .labelsHidden()
                .frame(width: 145)
                .accessibilityIdentifier("filter.confidence")
            }

            Menu("Select") {
                Button("None") { actions.clear() }
                Button("All Changeable") { actions.selectAll(flattened(filteredItems)) }
                Button("Needs Review") { actions.selectNeedingReview(flattened(filteredItems)) }
            }
            .frame(width: 80)
            .disabled(isBusy)
            .accessibilityIdentifier("filter.select")

            Spacer(minLength: 0)

            if filter.isActive {
                Button("Reset") { filter.reset() }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("filter.reset")
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
                        Text("What you can clean")
                            .font(.system(size: 15, weight: .semibold))

                        Spacer(minLength: 8)

                        Text("Select items; large files can be reviewed in Finder.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    itemList(items)
                }
            } else {
                itemList(items)
            }
        } else {
            firstRunView
        }
    }

    private func itemList(_ items: [ScanItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            rows(sortedForReview(items))
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                onToggle: {
                    guard !isBusy else { return }
                    actions.toggle(row.item)
                },
                quickActionTitle: quickActionTitle(for: row.item, isChild: row.isChild),
                onQuickAction: { performQuickAction(for: row.item, isChild: row.isChild) },
                controlsDisabled: isBusy
            )

            if index < display.count - 1 {
                Hairline()
                    .padding(.leading, row.isChild ? 56 : (showsCategory ? 66 : 48))
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
        if item.category == .disk && item.title == "Startup disk" && item.risk != .safe { return "Review caches" }
        if item.category == .memory && item.risk != .safe { return "Open Processes" }
        // While the list is stale (scan or batch running), hide mutating quick
        // actions. Navigation aids above stay available.
        if isBusy { return nil }
        guard item.canBeChanged else { return nil }

        switch item.action {
        case .killProcess:
            return "Quit"
        case .trashLeftover:
            return "Review"
        case .deleteSimulator, .deleteUnavailableSimulators:
            return "Delete"
        default:
            return nil
        }
    }

    private func performQuickAction(for item: ScanItem, isChild: Bool) {
        guard !isChild else { return }

        if item.isProtected {
            ActivityMonitor.open()
        } else if item.category == .disk && item.title == "Startup disk" && item.risk != .safe {
            page.selection = .category(.caches)
        } else if item.category == .memory && item.risk != .safe {
            page.selection = .category(.processes)
        } else {
            guard !isBusy else { return }
            actions.beginConfirmation(with: [item])
        }
    }

    private func sortedForReview(_ items: [ScanItem]) -> [ScanItem] {
        ReviewOrdering.sorted(items)
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
                        .accessibilityIdentifier("action-bar.status")

                    Spacer(minLength: 8)

                    if !selected.isEmpty {
                        Button("Deselect") { actions.clear() }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("action-bar.deselect")

                        Button(ActionExecutor.title(for: selected)) {
                            guard !isBusy else { return }
                            actions.beginConfirmation(with: selected)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(actions.isRunning || appState.isScanning)
                        .accessibilityIdentifier("action-bar.apply")
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
        let summary = DiskSpaceSummary.make(
            items: report.items,
            disk: report.disk,
            includesProtectedFolders: appState.includesProtectedFolders
        )
        let segments = summary.groups.map { group in
            BreakdownSegment(
                name: group.title,
                bytes: group.isMeasured ? group.bytes : 0,
                color: Self.color(for: group.kind)
            )
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Where your space goes")
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 8)

                Text("\(format(summary.usedBytes)) of \(format(summary.totalBytes)) used")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if summary.usedBytes > 0 {
                BreakdownBar(segments: segments, total: summary.usedBytes)
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(summary.groups) { group in
                    diskGroupRow(group)
                }
            }

            Button {
                showDiskDetails.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showDiskDetails ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))

                    Text("Show details")
                        .font(.system(size: 13, weight: .medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("disk.details")
            .accessibilityValue(showDiskDetails ? "Expanded" : "Collapsed")

            if showDiskDetails {
                diskDetails(summary, report: report)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showDiskDetails)
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// Friendly sub-buckets plus the single, explicitly technical entry point.
    @ViewBuilder
    private func diskDetails(_ summary: DiskSpaceSummary, report: ScanReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Keep the technical entry point at the top of the expanded area:
            // it is discoverable without scrolling past every sub-bucket.
            Button {
                showTechnicalDetails = true
            } label: {
                Label("How SiftBar measured this", systemImage: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            // A plain button with link styling stays a Button in the
            // accessibility tree; `.buttonStyle(.link)` is exposed as a Link
            // and its action is unreliable under XCUITest. A sheet also gives
            // the long technical list room without anchoring a popover inside
            // the page scroll view.
            .buttonStyle(.plain)
            .accessibilityIdentifier("disk.technical")
            .sheet(isPresented: $showTechnicalDetails) {
                DiskTechnicalDetailsView(report: report)
            }

            ForEach(summary.groups.filter(\.isMeasured)) { group in
                if !group.parts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.parts) { part in
                            HStack(spacing: 8) {
                                Text(part.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 8)

                                Text(format(part.bytes))
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

        }
        .padding(.top, 6)
    }

    /// One line of the space summary. The "Your files" row stays visible even
    /// when personal folders are not measured, with a single link to add access.
    @ViewBuilder
    private func diskGroupRow(_ group: DiskSpaceSummary.Group) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Self.color(for: group.kind))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(group.title)
                    .font(.system(size: 14, weight: .medium))

                Spacer(minLength: 8)

                if group.isMeasured {
                    Text(format(group.bytes))
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not measured")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Button("Add access") {
                        appState.presentAccessSheet()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("disk.addAccess")
                }
            }

            // The biggest bucket needs one plain sentence, otherwise it reads
            // as a mystery number. Other groups explain themselves on expand.
            if group.kind == .system || !group.isMeasured {
                Text(group.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(group.detail)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: group))
    }

    private func accessibilityLabel(for group: DiskSpaceSummary.Group) -> String {
        if group.isMeasured {
            return "\(group.title): \(format(group.bytes)). \(group.detail)"
        }
        return "\(group.title): not measured. \(group.detail)"
    }

    private static func color(for kind: DiskSpaceSummary.Kind) -> Color {
        switch kind {
        case .apps: return Color(nsColor: .systemBlue)
        case .files: return Color(nsColor: .systemTeal)
        case .appData: return Color(nsColor: .systemOrange)
        case .system: return Color(nsColor: .systemGray)
        }
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
            return reclaimStats(metrics, disk: report.disk)
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
                help: "Space used on this Mac, including macOS and protected files."
            ),
            Stat(
                value: format(report.disk.importantFreeBytes),
                label: "Free",
                tint: .primary,
                help: "Includes space macOS can free on demand, so it matches System Settings."
            ),
            Stat(
                value: format(metrics.diskReclaimableBytes),
                label: "Can be cleaned",
                tint: metrics.diskReclaimableBytes > 0 ? .green : .secondary,
                help: "Caches and reviewed leftovers SiftBar can move to the Trash. Empty the Trash to free the space."
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

    private func reclaimStats(_ metrics: ReviewMetrics, disk: DiskStats) -> [Stat] {
        // Only actionable rows count: the simulator summary is informational
        // and its devices may also appear individually, so summing every row
        // would double count.
        let cacheBytes = categoryItems(.caches, in: allItems)
            .filter(\.canBeChanged)
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
                label: "Can be cleaned",
                tint: cacheBytes > 0 ? .green : .secondary,
                help: "Caches, iPhone device support and simulator data SiftBar can remove. Simulators are deleted immediately; caches go to the Trash."
            ),
            Stat(
                value: "\(metrics.needReview)",
                label: "Need review",
                tint: reviewTint(metrics),
                help: "\(metrics.dangerous) dangerous · \(metrics.caution) caution"
            ),
            Stat(
                value: format(disk.importantFreeBytes),
                label: "Disk available",
                tint: diskTint(disk),
                help: "\(format(disk.importantFreeBytes)) available, matching System Settings · \(Int(disk.usedRatio * 100))% used"
            )
        ]
    }

    private func leftoverStats(_ metrics: ReviewMetrics) -> [Stat] {
        let items = categoryItems(.leftovers, in: allItems)
        let findings = items.filter { !$0.isInformational }
        // Low-confidence rows are context, not reclaimable data.
        let bytes = items.filter(\.canBeChanged).compactMap(\.impactBytes).reduce(0, +)

        return [
            Stat(
                value: "\(findings.count)",
                label: "Possible leftovers",
                tint: findings.isEmpty ? .secondary : .orange,
                help: "Application Support folders with no matching installed app. Low-confidence rows are not counted."
            ),
            Stat(
                value: format(bytes),
                label: "Reclaimable size",
                tint: .primary,
                help: "App data SiftBar can move to the Trash. Low-confidence rows and shared vendor folders are excluded."
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

        let summary = ActionResultSummary.make(
            changedCount: actions.changedCount,
            failedCount: actions.failedCount,
            reportCount: actions.reports.count,
            freedBytes: actions.diskFreedBytes,
            movedBytes: actions.diskMovedBytes,
            memoryBytes: actions.memoryReleasedBytes,
            formatDisk: { format($0) },
            formatMemory: { formatMemory(UInt64($0)) }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.headline)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("result.headline")

                    Text(summary.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Dismiss") { actions.dismissSummary() }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("result.dismiss")
            }
            // Do not combine the children: that would swallow the Dismiss
            // button into the headline element, hiding it from VoiceOver and
            // from UI tests.

            if actions.failedCount > 0 {
                HStack(spacing: 14) {
                    Button(actions.showsFailureDetails ? "Hide failure details" : "Show failure details") {
                        actions.showsFailureDetails.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.callout)

                    Button("Retry \(actions.failedItems.count) Failed \(actions.failedItems.count == 1 ? "Item" : "Items")…") {
                        actions.beginRetryOfFailures()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(actions.isRunning)
                }

                if actions.showsFailureDetails {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(actions.reports.filter { !$0.success }) { report in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(report.title)
                                    .font(.caption.weight(.medium))

                                Text(report.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }

            if summary.showsTrashButton {
                Button("Show Trash in Finder") {
                    openTrash()
                }
                .buttonStyle(.link)
                .font(.callout)
                .accessibilityIdentifier("result.show-trash")
            }
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
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

    private var firstRunView: some View {
        FirstRunView(
            includesProtectedFolders: appState.includesProtectedFolders,
            isBusy: isBusy || appState.isScanning,
            onAnalyze: { Task { await appState.analyze() } },
            onGrantAccess: { appState.presentAccessSheet() }
        )
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
        case .disk: return "See what's using space and clean only what you choose. SiftBar won't touch protected files."
        case .caches: return "Recreatable data. Moving it to the Trash slows the next run but keeps your files."
        case .leftovers: return "App data left behind by apps that are no longer installed. Review before deleting."
        }
    }

    // MARK: - Data

    /// True while the visible list is stale: a quick refresh or an action
    /// batch is running. Selection and mutating actions are disabled; the
    /// already-pruned succeeded items never reappear as stale rows. A
    /// background map refresh does not lock the list.
    private var isBusy: Bool {
        appState.locksInteraction || actions.isRunning
    }

    private var analyzeLabel: String {
        if actions.isRunning { return "Applying…" }
        if appState.isScanning { return "Analyzing…" }
        return "Analyze"
    }

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

    private func confidenceCount(_ confidence: LeftoverConfidence) -> Int {
        categoryItems(.leftovers, in: allItems)
            .filter { $0.leftoverConfidence == confidence }
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

    /// Saves the current report as Markdown. The renderer is pure; this method
    /// only owns the save panel. Nothing is written without the user choosing
    /// a destination.
    private func exportReport() {
        guard let report = appState.report else { return }

        let markdown = ReportExporter.markdown(
            for: report,
            includesProtectedFolders: appState.includesProtectedFolders
        )

        let panel = NSSavePanel()
        panel.title = "Export SiftBar Report"
        panel.prompt = "Export"
        panel.nameFieldStringValue = ReportExporter.suggestedFilename()
        // `UTType.markdown` is newer than the macOS 13 deployment target.
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSSound.beep()
            }
        }
    }

    private func openTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(trash)
    }

    private func confirmActions() {
        Task {
            // Capture targets before running: `pending` is cleared by `run()`.
            let targets = actions.pending
            appState.beginApplying()
            await actions.run()
            // Instant refresh: drop succeeded rows from every category view
            // (Disk and Caches share the same items) before the slow `du`
            // rescan finishes. Paths cover rescans that minted new IDs;
            // tombstones in AppState stop a raced scan from resurrecting them.
            // Failed rows stay for the rescan to correct.
            let succeeded = actions.succeededIDs
            if !succeeded.isEmpty {
                let paths = Set(
                    targets
                        .filter { succeeded.contains($0.id) }
                        .compactMap { $0.action.targetPath }
                )
                appState.removeItems(withIDs: succeeded, paths: paths)
            }
            appState.endApplying()
            // Fast refresh first: the list and counts update in a couple of
            // seconds. The slow `du` space map then catches up in the
            // background without freezing selection.
            await appState.refreshQuickly()
            await appState.refreshInBackground()
        }
    }
}

private struct DisplayRow: Identifiable {
    let item: ScanItem
    let isChild: Bool

    var id: UUID { item.id }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }
}
