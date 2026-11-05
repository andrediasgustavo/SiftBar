import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Open Dashboard") {
            DashboardWindowController.shared.show(state: appState)
        }
        .keyboardShortcut("d")

        Button(appState.isScanning ? "Analyzing..." : "Run Analysis") {
            Task { await appState.analyze() }
        }
        .keyboardShortcut("r")
        .disabled(appState.isScanning)

        Divider()

        Text(appState.status)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit SiftBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
