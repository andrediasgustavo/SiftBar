import AppKit
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
            Label(menuBarTitle, systemImage: menuBarSymbol)
        }
    }

    private var menuBarTitle: String {
        guard let report = appState.report else { return "SiftBar" }

        let findings = report.items.filter { !$0.isInformational }
        let review = findings.filter { $0.risk != .safe }.count
        return review == 0 ? "SiftBar · all clear" : "SiftBar · \(review) need review"
    }

    private var menuBarSymbol: String {
        if appState.isScanning { return "arrow.triangle.2.circlepath" }

        if let report = appState.report,
           report.items.contains(where: { !$0.isInformational && $0.risk == .dangerous }) {
            return "exclamationmark.triangle.fill"
        }

        return "line.3.horizontal.decrease"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no main window at launch.
        NSApp.setActivationPolicy(.accessory)

        // Development hooks:
        //   open SiftBar.app --args --show-dashboard
        //   open SiftBar.app --args --show-dashboard --analyze
        if CommandLine.arguments.contains("--show-dashboard") {
            DashboardWindowController.shared.show(state: AppState.shared)

            if CommandLine.arguments.contains("--analyze") {
                Task { await AppState.shared.analyze() }
            }
        }
    }
}

extension Notification.Name {
    static let siftBarShowHistory = Notification.Name("SiftBarShowHistory")
    static let siftBarFocusSearch = Notification.Name("SiftBarFocusSearch")
}
