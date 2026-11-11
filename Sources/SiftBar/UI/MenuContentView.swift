import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("SiftBar")
            .font(.headline)

        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)

        Divider()

        Button("Open Dashboard") {
            DashboardWindowController.shared.show(state: appState)
        }
        .keyboardShortcut("d")

        Button(menuAnalyzeLabel) {
            Task { await appState.analyze() }
        }
        .keyboardShortcut("r")
        .disabled(appState.isScanning || appState.isApplying)

        Button("History…") {
            DashboardWindowController.shared.show(state: appState)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .siftBarShowHistory, object: nil)
            }
        }
        .keyboardShortcut("y")

        Divider()

        Button("Quit SiftBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusTint: Color {
        if appState.isScanning || appState.isApplying { return .orange }
        guard let report = appState.report else { return .secondary }

        let findings = report.items.filter { !$0.isInformational }
        if findings.contains(where: { $0.risk == .dangerous }) { return .red }
        if findings.contains(where: { $0.risk == .caution }) { return .orange }
        return .green
    }

    private var statusText: String {
        if appState.isScanning { return "Analyzing…" }
        if appState.isApplying { return "Applying…" }
        guard let report = appState.report else { return "Ready to analyze" }

        let findings = report.items.filter { !$0.isInformational }
        let review = findings.filter { $0.risk != .safe }.count
        if review == 0 {
            return "All clear · \(findings.count) findings"
        }

        return "\(review) need review · \(findings.count) findings"
    }

    private var menuAnalyzeLabel: String {
        if appState.isScanning { return "Analyzing…" }
        if appState.isApplying { return "Applying…" }
        return "Run Analysis"
    }
}
