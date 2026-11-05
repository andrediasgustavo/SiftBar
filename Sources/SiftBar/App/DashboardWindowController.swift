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

            // A plain NSView container keeps the window from being resized to
            // the hosting view's intrinsic (minimum) size.
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 700))
            container.translatesAutoresizingMaskIntoConstraints = true
            container.autoresizingMask = [.width, .height]

            hostingView.translatesAutoresizingMaskIntoConstraints = true
            hostingView.autoresizingMask = [.width, .height]
            hostingView.frame = container.bounds
            container.addSubview(hostingView)

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "SiftBar"
            newWindow.contentView = container
            newWindow.setContentSize(NSSize(width: 820, height: 700))
            newWindow.contentMinSize = NSSize(width: 700, height: 560)
            newWindow.isReleasedWhenClosed = false
            newWindow.center()

            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
