import AppKit
import SwiftUI

struct ItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let canSelect: Bool
    let showsCategory: Bool
    let isChild: Bool
    let hasChildren: Bool
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onToggle: () -> Void
    let quickActionTitle: String?
    let onQuickAction: (() -> Void)?
    /// True while a scan or an action batch is running. Selection and quick
    /// actions are disabled so a stale row cannot be acted on twice; Finder
    /// reveal and copy stay enabled.
    let controlsDisabled: Bool

    @StateObject private var hover = HoverModel()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            selectionControl
                .frame(width: 18, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                titleLine
                detailLine
                warningLine
                evidenceLine
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .padding(.leading, isChild ? 26 : 0)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) { riskRail }
        .contentShape(Rectangle())
        .onHover { hover.isHovered = $0 }
        .contextMenu {
            if let url = item.revealURL {
                Button("Show in Finder") { FinderReveal.show(url) }
                Divider()
            }

            if item.category == .processes {
                Button("Open in Activity Monitor") { ActivityMonitor.open() }
                Divider()
            }

            Button("Copy Evidence") { copy(item.evidence) }
            Button("Copy Summary") { copy("\(item.title) — \(item.detail)") }
        }
    }

    // MARK: - Lines

    private var titleLine: some View {
        HStack(alignment: .center, spacing: 6) {
            if hasChildren {
                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide individual processes" : "Show individual processes")
                .accessibilityLabel(isExpanded ? "Collapse processes" : "Expand processes")
            }

            if showsCategory {
                Image(systemName: item.category.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(item.category.title)
            }

            Text(item.title)
                .font(isChild ? .callout.weight(.medium) : .body.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let quickActionTitle, let onQuickAction, !isChild {
                Button(quickActionTitle, action: onQuickAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(controlsDisabled)
            }

            Text(item.impactLabel)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 70, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        if showsDetail {
            Text(item.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(item.detail)
        }
    }

    /// Cache rows all share the same boilerplate sentence, which is already in
    /// the page description. Hide only that sentence so a future item-specific
    /// detail still shows up.
    private var showsDetail: Bool {
        if item.category == .caches && item.detail.hasPrefix("Recreatable cache data.") {
            return false
        }
        return !item.detail.isEmpty
    }

    @ViewBuilder
    private var warningLine: some View {
        if let warning = item.warning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var evidenceLine: some View {
        HStack(spacing: 6) {
            Image(systemName: item.revealURL == nil ? "terminal" : "folder")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            Text(item.displayEvidence)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(item.evidence)

            Spacer(minLength: 8)

            // Keep the risk word visible: the rail is a scanning aid, not the
            // only carrier of risk. Screen readers get it in the checkbox label.
            Text(item.isProtected ? "Protected" : (item.isInformational ? "Info" : item.risk.label))
                .font(.caption2.weight(.medium))
                .foregroundStyle(item.risk == .dangerous ? Color(nsColor: .systemRed) : Color.secondary)
                .lineLimit(1)

            if let url = item.revealURL {
                Button {
                    FinderReveal.show(url)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hover.isHovered ? 1 : 0)
                .allowsHitTesting(hover.isHovered)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
        }
        .help("Source and command")
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionControl: some View {
        if canSelect {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(controlsDisabled)
            .accessibilityLabel(
                isSelected
                    ? "Deselect \(item.title), \(accessibilityRisk)"
                    : "Select \(item.title), \(accessibilityRisk)"
            )
            .help(isSelected ? "Deselect" : "Select")
        } else {
            Image(systemName: item.requiresAdmin || item.isProtected ? "lock.fill" : "minus")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
                .help(helpText)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityRisk: String {
        if item.isProtected { return "protected" }
        if item.isInformational { return "informational" }
        return item.risk.label.lowercased()
    }

    private var helpText: String {
        if item.isProtected {
            return "Protected system process. SiftBar will not quit it; open Activity Monitor for details."
        }
        if item.requiresAdmin {
            return "Requires administrator rights. SiftBar will not change it."
        }
        return "SiftBar will not change this item."
    }

    private var accessibilityText: String {
        if item.isProtected { return "Protected system process" }
        return item.requiresAdmin ? "Requires administrator rights" : "Not changeable"
    }

    /// The risk rail is the row's at-a-glance signal. It is decorative: the
    /// risk word stays in the metadata line and in the selection label, so
    /// nothing is conveyed by color alone.
    private var riskRail: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(railColor)
            .frame(width: 3)
            .padding(.vertical, 7)
            .accessibilityHidden(true)
    }

    private var railColor: Color {
        if item.isProtected || item.isInformational {
            return Color(nsColor: .tertiaryLabelColor)
        }

        switch item.risk {
        case .safe: return Color(nsColor: .systemGreen)
        case .caution: return Color(nsColor: .systemOrange)
        case .dangerous: return Color(nsColor: .systemRed)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if hover.isHovered { return Color.primary.opacity(0.045) }
        return .clear
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension ScanItem {
    /// Human-readable evidence for the row. Trash actions expose their exact
    /// path (with the home folder abbreviated); other rows keep their command
    /// but still abbreviate paths. The full command remains in the
    /// confirmation sheet and in "Copy Evidence".
    var displayEvidence: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let raw = action.targetPath ?? evidence

        guard !home.isEmpty, raw.hasPrefix(home + "/") else { return raw }
        return "~" + String(raw.dropFirst(home.count))
    }
}

/// `@State` is a macro in recent SwiftUI SDKs; using `@StateObject` keeps the
/// direct-`swiftc` build working with Command Line Tools only.
private final class HoverModel: ObservableObject {
    @Published var isHovered = false
}

/// Opens a folder in Finder, or reveals and selects a file.
enum FinderReveal {
    static func show(_ url: URL) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue && url.pathExtension.lowercased() != "app" {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// Protected processes cannot be quit from SiftBar. Activity Monitor is the
/// right place to inspect them, so the row offers that instead of a dead end.
enum ActivityMonitor {
    static func open() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }
}

extension Risk {
    var tint: Color {
        switch self {
        case .safe: return Color(nsColor: .systemGreen)
        case .caution: return Color(nsColor: .systemOrange)
        case .dangerous: return Color(nsColor: .systemRed)
        }
    }

    /// Highest risk first, so the list reads as a triage queue.
    var sortRank: Int {
        switch self {
        case .dangerous: return 0
        case .caution: return 1
        case .safe: return 2
        }
    }
}
