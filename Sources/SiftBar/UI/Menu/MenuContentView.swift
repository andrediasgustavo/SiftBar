import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("SiftBar")
            .font(.headline)

        // The menu bar popover uses the native `.menu` style, which renders
        // content as menu items and drops custom `HStack`/`Image` views. The
        // status dot therefore lives inside the Text as an emoji glyph, the
        // only form that keeps its color in a native menu item.
        Text("\(statusDot) \(statusText)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
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

    private var statusDot: String {
        MenuStatus.dot(
            isScanning: appState.isScanning,
            isApplying: appState.isApplying,
            report: appState.report
        )
    }

    private var statusText: String {
        MenuStatus.text(
            isScanning: appState.isScanning,
            isApplying: appState.isApplying,
            report: appState.report
        )
    }

    private var menuAnalyzeLabel: String {
        MenuStatus.analyzeLabel(
            isScanning: appState.isScanning,
            isApplying: appState.isApplying
        )
    }
}
