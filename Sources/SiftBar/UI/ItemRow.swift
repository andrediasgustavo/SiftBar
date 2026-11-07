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

    @StateObject private var hover = HoverModel()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            selectionControl
                .frame(width: 16, alignment: .leading)

            riskColumn
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if hasChildren {
                            Button(action: onToggleExpanded) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12, height: 16)
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
                    }

                    Spacer(minLength: 8)

                    Text(item.impactLabel)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 70, alignment: .trailing)

                    if let quickActionTitle, let onQuickAction, !isChild {
                        Button(quickActionTitle, action: onQuickAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let warning = item.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                evidence
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .padding(.leading, isChild ? 26 : 0)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    @ViewBuilder
    private var selectionControl: some View {
        if canSelect {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(item.title)" : "Select \(item.title)")
            .help(isSelected ? "Deselect" : "Select")
        } else {
            Image(systemName: item.requiresAdmin || item.isProtected ? "lock.fill" : "minus")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .help(helpText)
                .accessibilityLabel(accessibilityText)
        }
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

    /// A fixed-width risk column keeps every title on the same vertical line.
    private var riskColumn: some View {
        HStack(spacing: 6) {
            if item.isProtected {
                Image(systemName: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Protected")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if item.isInformational {
                Circle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)

                Text("Info")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                RiskDot(risk: item.risk)

                Text(item.risk.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(item.risk == .dangerous ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The product promise is full transparency: the source stays readable and
    /// copyable rather than being decorative fine print.
    private var evidence: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(item.evidence)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let url = item.revealURL {
                Spacer(minLength: 8)

                Button {
                    FinderReveal.show(url)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
        }
        .help("Source and command")
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

/// `@State` is a macro in recent SwiftUI SDKs; using `@StateObject` keeps the
/// direct-`swiftc` build working with Command Line Tools only.
private final class HoverModel: ObservableObject {
    @Published var isHovered = false
}

private struct RiskDot: View {
    let risk: Risk

    var body: some View {
        Group {
            if risk == .safe {
                Circle()
                    .strokeBorder(Color(nsColor: .systemGreen).opacity(0.8), lineWidth: 1.2)
            } else {
                Circle()
                    .fill(risk.tint)
            }
        }
        .frame(width: 7, height: 7)
    }
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
