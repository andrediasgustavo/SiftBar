import Foundation

/// Pure presentation rules for the menu bar popover.
///
/// Kept outside the view so the status dot and label can be unit-tested: a
/// custom `HStack`/`Image` does not survive the native `.menu` style, so the
/// dot must remain an emoji inside the text.
enum MenuStatus {
    static func dot(isScanning: Bool, isApplying: Bool, report: ScanReport?) -> String {
        if isScanning || isApplying { return "🟠" }
        guard let report else { return "⚪️" }

        let findings = report.items.filter { !$0.isInformational }
        if findings.contains(where: { $0.risk == .dangerous }) { return "🔴" }
        if findings.contains(where: { $0.risk == .caution }) { return "🟠" }
        return "🟢"
    }

    static func text(isScanning: Bool, isApplying: Bool, report: ScanReport?) -> String {
        if isScanning { return "Analyzing…" }
        if isApplying { return "Applying…" }
        guard let report else { return "Ready to analyze" }

        let findings = report.items.filter { !$0.isInformational }
        let review = findings.filter { $0.risk != .safe }.count
        if review == 0 {
            return "All clear · \(findings.count) findings"
        }

        return "\(review) need review · \(findings.count) findings"
    }

    static func analyzeLabel(isScanning: Bool, isApplying: Bool) -> String {
        if isScanning { return "Analyzing…" }
        if isApplying { return "Applying…" }
        return "Run Analysis"
    }
}

/// Presentation rules for the dashboard header.
enum DashboardPresentation {
    /// While no report exists the first-run screen owns the only primary
    /// action, so the header hides its own Analyze button.
    static func showsHeaderAnalyze(report: ScanReport?) -> Bool {
        report != nil
    }
}
