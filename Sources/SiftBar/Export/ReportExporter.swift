import Foundation

/// Renders a scan report as Markdown. Read-only: the exporter never runs an
/// action or touches the filesystem beyond reading the home path for
/// abbreviation.
enum ReportExporter {
    static func markdown(
        for report: ScanReport,
        version: String = appVersion(),
        includesProtectedFolders: Bool,
        generatedAt: Date = Date()
    ) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let metrics = ReviewMetrics.make(visible: report.items, all: report.items)

        var lines: [String] = []
        lines.append("# SiftBar report")
        lines.append("")
        lines.append("- Generated: \(dateString(generatedAt))")
        lines.append("- SiftBar: \(version)")
        lines.append("- Personal folders (Desktop, Documents, Downloads): \(includesProtectedFolders ? "measured" : "skipped")")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("- Findings: \(metrics.findings) (\(metrics.needReview) need review)")
        lines.append("- Caution: \(metrics.caution) · Dangerous: \(metrics.dangerous) · Informational: \(metrics.informational)")
        lines.append("- Disk space SiftBar can move to the Trash: \(bytes(metrics.diskReclaimableBytes))")
        lines.append("- Memory SiftBar can release by quitting apps: \(memoryBytes(metrics.memoryReleasableBytes))")
        lines.append("- Disk: \(bytes(report.disk.usedBytes)) used of \(bytes(report.disk.totalBytes))")
        lines.append("- Memory: \(memoryBytes(Int64(report.memory.usedBytes))) used of \(memoryBytes(Int64(report.memory.totalBytes))) · pressure \(report.memory.pressure.label)")
        lines.append("")

        let findings = report.items.filter { !$0.isInformational && !$0.isBreakdown }
        lines.append("## Findings")
        lines.append("")
        if findings.isEmpty {
            lines.append("No findings.")
            lines.append("")
        } else {
            lines.append(contentsOf: itemSections(findings, home: home))
        }

        let context = report.items.filter { $0.isInformational && !$0.isBreakdown }
        if !context.isEmpty {
            lines.append("## Read-only context")
            lines.append("")
            lines.append("These rows explain the system and cannot be changed from SiftBar.")
            lines.append("")
            lines.append(contentsOf: itemSections(context, home: home))
        }

        let breakdown = report.items.filter(\.isBreakdown).sorted {
            ($0.impactBytes ?? 0) > ($1.impactBytes ?? 0)
        }
        if !breakdown.isEmpty {
            lines.append("## Disk map")
            lines.append("")
            for item in breakdown {
                lines.append("- **\(inline(item.title))** — \(item.impactLabel)")
                for child in item.children {
                    lines.append("  - \(inline(child.title)) — \(child.impactLabel)")
                }
            }
            lines.append("")
        }

        let history = report.items
            .compactMap { item -> String? in
                guard let warning = item.warning else { return nil }
                return "- \(inline(item.title)): \(inline(warning))"
            }
        if !history.isEmpty {
            lines.append("## Warnings")
            lines.append("")
            lines.append(contentsOf: history)
            lines.append("")
        }

        lines.append("## Notes")
        lines.append("")
        lines.append("- This report is read-only. No command was run to produce it.")
        lines.append("- \"Move to Trash\" does not free disk space until the Trash is emptied.")
        lines.append("- Disk bytes and memory bytes are never added together.")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    static func suggestedFilename(for date: Date = Date()) -> String {
        "SiftBar-Report-\(dateString(date, format: "yyyy-MM-dd")).md"
    }

    static func appVersion(bundle: Bundle = .main) -> String {
        guard let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.isEmpty else {
            return "dev"
        }

        if let build = bundle.infoDictionary?["CFBundleVersion"] as? String,
           !build.isEmpty {
            return "\(short) (\(build))"
        }

        return short
    }

    // MARK: - Sections

    private static func itemSections(_ items: [ScanItem], home: String) -> [String] {
        var lines: [String] = []

        for category in ItemCategory.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let batch = items.filter { $0.category == category }
            guard !batch.isEmpty else { continue }

            lines.append("### \(category.title)")
            lines.append("")

            for item in batch.sorted(by: { ($0.impactBytes ?? 0) > ($1.impactBytes ?? 0) }) {
                let label = item.isInformational ? "Info" : item.risk.label
                lines.append("- **[\(label)] \(inline(redact(item.title, home: home)))** — \(item.impactLabel)")

                if let confidence = item.leftoverConfidence {
                    lines.append("  - Confidence: \(confidence.label)")
                }

                if !item.detail.isEmpty {
                    lines.append("  - \(inline(redact(item.detail, home: home)))")
                }

                if !item.evidence.isEmpty {
                    lines.append("  - Evidence: \(code(redact(item.evidence, home: home)))")
                }

                if item.canBeChanged {
                    lines.append("  - Command: \(code(redact(ActionExecutor.preview(for: item), home: home)))")
                } else if item.requiresAdmin {
                    lines.append("  - Locked: requires administrator rights.")
                } else if item.leftoverConfidence == .low {
                    lines.append("  - Locked: review it in Finder first.")
                }

                if let warning = item.warning {
                    lines.append("  - Warning: \(inline(redact(warning, home: home)))")
                }

                for child in item.children {
                    lines.append("  - \(inline(redact(child.title, home: home))) — \(child.impactLabel)")
                }
            }

            lines.append("")
        }

        return lines
    }

    // MARK: - Formatting

    static func redact(_ text: String, home: String) -> String {
        guard !home.isEmpty else { return text }
        return text
            .replacingOccurrences(of: home + "/", with: "~/")
            .replacingOccurrences(of: home, with: "~")
    }

    private static func inline(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
        for character in ["*", "_", "`", "[", "]"] {
            escaped = escaped.replacingOccurrences(of: character, with: "\\" + character)
        }
        return escaped
    }

    private static func code(_ text: String) -> String {
        guard !text.contains("`") else {
            return "```\n\(text)\n```"
        }
        return "`\(text)`"
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static func memoryBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    private static func dateString(_ date: Date, format: String = "yyyy-MM-dd HH:mm") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
