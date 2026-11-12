import AppKit
import Foundation
import SwiftUI

/// How an interactive scan is presented. Quick refreshes and background map
/// refreshes stay on the compact header indicator.
enum ScanPresentation: Equatable {
    case none
    case workspace
    case banner
    /// Thin progress line used by the background map refresh: feedback without
    /// dimming or disabling the list.
    case slim
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isScanning = false
    @Published private(set) var locksInteraction = false
    @Published private(set) var isApplying = false
    @Published private(set) var status = "Ready to analyze."
    @Published private(set) var scanPresentation: ScanPresentation = .none
    @Published private(set) var scanProgress: ScanProgress?
    @Published private(set) var report: ScanReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastDuration: TimeInterval?
    @Published private(set) var accessStatus: FullDiskAccess.Status = .unknown
    @Published private(set) var includesProtectedFolders = false
    @Published private(set) var accessHint: String?
    @Published private(set) var hasOpenedAccessSettings = false
    @Published private(set) var isRestarting = false
    @Published var isAccessSheetPresented = false

    private let onboardingKey = "SiftBar.hasSeenAccessOnboarding"
    #if SIFTBAR_DEMO
    private var demoMode = false
    #endif
    private var scanInFlight = false
    private var activeScanTask: Task<ScanReport, Never>?
    /// True when the report is being refreshed after a confirmed action
    /// batch. The status line must not claim "nothing has been changed"
    /// in that case.
    private var isPostActionRefresh = false
    /// Paths removed by confirmed actions, with the removal time. A scan that
    /// started before the Trash move finished (or a ⌘R fired mid-batch) would
    /// otherwise bring the stale row back with a brand-new ID. Entries expire
    /// quickly: a cache the app recreates shows up again on the next scan.
    private var deletedPaths: [String: Date] = [:]
    private static let tombstoneLifetime: TimeInterval = 120

    /// `refreshAccess: false` keeps UI/snapshot tests deterministic and avoids
    /// probing the user's TCC state when only layout is under test.
    init(refreshAccess: Bool = true) {
        if refreshAccess {
            self.refreshAccess()
        }
    }

    var showsPartialDiskData: Bool {
        !includesProtectedFolders
    }

    var accessStatusText: String {
        if accessStatus == .granted {
            return "Full Disk Access detected"
        }
        if includesProtectedFolders {
            return "Folder-by-folder access enabled"
        }
        return "Personal folders not included"
    }

    var hasSeenAccessOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func analyze() async {
        isPostActionRefresh = false
        await performScan(quick: false, locksUI: true)
    }

    /// Refresh used right after a confirmed action batch. Skips the slow `du`
    /// collectors (space map, large consumers) so the list and counts update
    /// in a couple of seconds; the previous map rows are kept until the
    /// background pass replaces them.
    func refreshQuickly() async {
        isPostActionRefresh = true
        await performScan(quick: true, locksUI: true)
    }

    /// Full refresh that does not disable the list, so the space map can catch
    /// up after a quick refresh without freezing selection.
    func refreshInBackground() async {
        await performScan(quick: false, locksUI: false)
    }

    private func performScan(quick: Bool, locksUI: Bool) async {
        guard !scanInFlight, !isApplying else { return }

        scanInFlight = true
        #if SIFTBAR_DEMO
        demoMode = false
        #endif
        refreshAccess()
        errorMessage = nil
        isScanning = true
        locksInteraction = locksUI

        // The full workspace is for scans without data; with a previous report
        // the banner keeps the results visible. Post-action quick refreshes
        // show the banner too (the user just changed something and expects
        // feedback), and the background map refresh uses a thin line so the
        // list stays usable.
        let presentation: ScanPresentation
        if locksUI {
            presentation = report == nil ? .workspace : .banner
        } else if isPostActionRefresh && report != nil {
            presentation = .slim
        } else {
            presentation = .none
        }
        scanPresentation = presentation
        scanProgress = presentation == .none
            ? nil
            : ScanProgress(step: 1, fraction: 0.02, message: "Reading system information")

        if isPostActionRefresh {
            status = quick
                ? "Updating after your changes…"
                : "Refreshing the space map…"
        } else if locksUI {
            status = "Scanning memory, processes, startup items, services, disk, caches and leftovers..."
        } else {
            status = "Refreshing the space map in the background…"
        }

        defer {
            scanInFlight = false
            isScanning = false
            locksInteraction = false
            scanPresentation = .none
            scanProgress = nil
            activeScanTask = nil
        }

        var progressHandler: (@Sendable (ScanProgress) -> Void)?
        if presentation != .none {
            progressHandler = { [weak self] progress in
                DispatchQueue.main.async {
                    guard let self, self.scanPresentation != .none else { return }
                    self.scanProgress = progress
                }
            }
        }

        let startedAt = Date()
        let task = Task {
            await ScanCoordinator.run(
                includeProtectedFolders: includesProtectedFolders,
                includeSlowCollectors: !quick,
                progress: progressHandler
            )
        }
        activeScanTask = task
        var result = await task.value
        let cancelled = task.isCancelled
        activeScanTask = nil

        if cancelled {
            status = "Analysis stopped."
            errorMessage = nil
            return
        }

        if quick, let current = report {
            result = result.mergingSlowItems(from: current)
        }
        result = result.removingItems(withIDs: [], paths: activeTombstones())

        // Surface a total probe failure instead of showing an empty report.
        errorMessage = result.failedToReadSystem
            ? "System information could not be read. Try again."
            : nil

        report = result
        let duration = Date().timeIntervalSince(startedAt)
        lastDuration = duration

        if isPostActionRefresh {
            // Never say "nothing has been changed" right after the user
            // moved items to the Trash; the result card already reports it.
            status = String(
                format: "Updated in %.1fs · %d items found",
                duration,
                result.items.count
            )
        } else {
            status = String(
                format: "Found %d items in %.1fs. Nothing has been changed.",
                result.items.count,
                duration
            )
        }
    }

    /// Cancels the running scan. The previous report (if any) is kept and the
    /// workspace/banner closes immediately.
    func cancelScan() {
        activeScanTask?.cancel()
    }

    /// Marks the start/end of a confirmed action batch. While applying, new
    /// scans are refused so a stale `du` walk cannot overwrite the instant
    /// prune that already removed the rows from every category.
    func beginApplying() {
        isApplying = true
    }

    func endApplying() {
        isApplying = false
    }

    func refreshAccess() {
        #if SIFTBAR_DEMO
        if demoMode {
            accessStatus = .granted
            includesProtectedFolders = true
            return
        }
        #endif

        accessStatus = FullDiskAccess.status()
        includesProtectedFolders = accessStatus == .granted || FullDiskAccess.allowsFolderPrompts
    }

    /// Shown once, the first time the dashboard opens. It is optional: the app
    /// already works without it and the user can dismiss it.
    func presentAccessSheetIfNeeded() {
        #if SIFTBAR_DEMO
        // Demo access is explicit via --demo-access. Do not let onAppear
        // refresh the synthetic denied state back to the demo's granted map.
        if demoMode { return }
        #endif

        refreshAccess()

        guard !includesProtectedFolders, !hasSeenAccessOnboarding else { return }
        isAccessSheetPresented = true
    }

    func presentAccessSheet() {
        refreshAccess()

        #if SIFTBAR_DEMO
        if demoMode {
            // Screenshots and UI tests need to exercise the state the flow is
            // asking the user to change, not a contradictory "detected" label.
            accessStatus = .denied
            includesProtectedFolders = false
        }
        #endif

        isAccessSheetPresented = true
    }

    func skipAccess() {
        markOnboardingSeen()
        accessHint = nil
        hasOpenedAccessSettings = false
        isAccessSheetPresented = false
    }

    func markOnboardingSeen() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    func openFullDiskAccessSettings() {
        hasOpenedAccessSettings = true
        accessHint = nil

        #if SIFTBAR_DEMO
        // UI tests exercise the flow without opening System Settings.
        if demoMode { return }
        #endif

        FullDiskAccess.openSettings()
    }

    /// Reopens a new process before ending this one. A new Full Disk Access
    /// grant is applied to that process, which then checks access automatically.
    /// Creating the new instance explicitly avoids `open` merely activating the
    /// old instance, and a launch failure leaves this session untouched.
    func restartAndCheckAccess() {
        guard !isRestarting else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            accessHint = "SiftBar can only restart from its app bundle. Open SiftBar.app and try again."
            return
        }

        isRestarting = true
        accessHint = nil

        // SwiftUI sheets can cancel NSApp.terminate. Launch only from the
        // sheet's onDismiss callback, when SwiftUI has finished removing the
        // presentation, instead of racing its dismissal animation.
        if isAccessSheetPresented {
            isAccessSheetPresented = false
        } else {
            launchRelaunchInstance()
        }
    }

    func accessSheetDidDismiss() {
        guard isRestarting else { return }
        launchRelaunchInstance()
    }

    private func launchRelaunchInstance() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = restartArguments

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.isRestarting = false
                    self.accessHint = "SiftBar could not reopen: \(error.localizedDescription). This session is still open; try again."
                    self.isAccessSheetPresented = true
                    return
                }

                NSApp.terminate(nil)
            }
        }
    }

    /// Entry point used only by the relaunched process. There is no separate
    /// "check again" action: checking is part of finishing the restart.
    func resumeAccessCheckAfterRestart() {
        refreshAccess()

        #if SIFTBAR_DEMO
        if demoMode {
            accessHint = nil
            markOnboardingSeen()
            isAccessSheetPresented = false
            return
        }
        #endif

        if includesProtectedFolders {
            completeAccessAndAnalyze()
        } else {
            hasOpenedAccessSettings = true
            accessHint = "SiftBar still cannot read Desktop, Documents and Downloads. Make sure SiftBar is enabled in Full Disk Access, then restart and check again."
            isAccessSheetPresented = true
        }
    }

    private func completeAccessAndAnalyze() {
        accessHint = nil
        hasOpenedAccessSettings = false
        isRestarting = false
        markOnboardingSeen()
        isAccessSheetPresented = false
        Task { await analyze() }
    }

    private var restartArguments: [String] {
        var arguments = ["--show-dashboard", "--resume-access-check"]

        #if SIFTBAR_DEMO
        if demoMode {
            arguments.append("--demo")
        }
        #endif

        return arguments
    }

    func useFolderPrompts() {
        FullDiskAccess.setAllowsFolderPrompts(true)
        refreshAccess()
        completeAccessAndAnalyze()
    }

    #if SIFTBAR_DEMO
    /// Synthetic data for README screenshots. Never used by a normal scan.
    func loadDemoReport() {
        demoMode = true
        report = DemoReport.make()
        lastDuration = 1.2
        status = "Found 24 items in 1.2s. Nothing has been changed."
        includesProtectedFolders = true
        accessStatus = .granted
        isAccessSheetPresented = false
        accessHint = nil
        errorMessage = nil
    }
    #endif

    func clearReport() {
        report = nil
        lastDuration = nil
        status = "Ready to analyze."
        errorMessage = nil
    }

    private func activeTombstones(now: Date = Date()) -> Set<String> {
        purgeTombstones(now: now)
        return Set(deletedPaths.keys)
    }

    private func purgeTombstones(now: Date) {
        deletedPaths = deletedPaths.filter {
            now.timeIntervalSince($0.value) < Self.tombstoneLifetime
        }
    }

    /// Removes succeeded items immediately so every category (Overview, Disk,
    /// Caches) stops offering them while the slower full rescan runs. Paths
    /// are tombstoned briefly so a scan that raced the batch cannot resurrect
    /// the rows with new IDs.
    func removeItems(withIDs ids: Set<UUID>, paths: Set<String> = []) {
        guard !ids.isEmpty || !paths.isEmpty else { return }
        let now = Date()
        for path in paths {
            deletedPaths[path] = now
            // Drop any cached measurement for the removed tree so a recreated
            // cache is walked again instead of showing stale bytes.
            SizeCache.shared.invalidate(path: path)
        }
        purgeTombstones(now: now)
        guard let current = report else { return }
        report = current.removingItems(withIDs: ids, paths: paths)
    }
}
