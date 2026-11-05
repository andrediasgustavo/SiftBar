import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("SiftBar")
            .font(.headline)

        Text("\(statusDot) \(statusText)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityLabel(statusText)

        Divider()

        Button("Open Dashboard") {
            DashboardWindowController.shared.show(state: appState)
        }
        .keyboardShortcut("d")

        Button(appState.isScanning ? "Analyzing…" : "Run Analysis") {
            Task { await appState.analyze() }
        }
        .keyboardShortcut("r")
        .disabled(appState.isScanning)

        Divider()

        Button("Quit SiftBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusDot: String {
        if appState.isScanning { return "🟠" }
        guard let report = appState.report else { return "⚪️" }

        if report.items.contains(where: { $0.risk == .dangerous }) { return "🔴" }
        if report.items.contains(where: { $0.risk == .caution }) { return "🟠" }
        return "🟢"
    }

    private var statusText: String {
        if appState.isScanning { return "Analyzing…" }
        guard let report = appState.report else { return "Ready to analyze" }

        let review = report.items.filter { $0.risk != .safe }.count
        if review == 0 {
            return "All clear · \(report.items.count) items"
        }

        return "\(review) need review · \(report.items.count) items"
    }
}
