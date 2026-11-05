import SwiftUI

@main
struct SiftBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            Label("SiftBar", systemImage: "waveform.path.ecg")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no main window at launch.
        NSApp.setActivationPolicy(.accessory)

        // Development hook: `open SiftBar.app --args --show-dashboard`.
        if CommandLine.arguments.contains("--show-dashboard") {
            DashboardWindowController.shared.show(state: AppState.shared)
        }
    }
}
