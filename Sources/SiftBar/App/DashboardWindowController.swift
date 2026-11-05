import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController {
    static let shared = DashboardWindowController()

    private var window: NSWindow?

    private init() {}

    func show(state: AppState) {
        if window == nil {
            let rootView = DashboardView().environmentObject(state)
            let hostingView = NSHostingView(rootView: rootView)

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "SiftBar"
            newWindow.contentView = hostingView
            newWindow.contentMinSize = NSSize(width: 640, height: 420)
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrameAutosaveName("SiftBarDashboard")
            newWindow.center()

            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
