import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isScanning = false
    @Published private(set) var locksInteraction = false
    @Published private(set) var isApplying = false
    @Published private(set) var status = "Ready to analyze."
    @Published private(set) var report: ScanReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastDuration: TimeInterval?
    @Published private(set) var accessStatus: FullDiskAccess.Status = .unknown
    @Published private(set) var includesProtectedFolders = false
    @Published private(set) var accessHint: String?
    @Published var isAccessSheetPresented = false

    private let onboardingKey = "SiftBar.hasSeenAccessOnboarding"
    private var demoMode = false
    private var scanInFlight = false
    /// Paths removed by confirmed actions, with the removal time. A scan that
    /// started before the Trash move finished (or a ⌘R fired mid-batch) would
    /// otherwise bring the stale row back with a brand-new ID. Entries expire
    /// quickly: a cache the app recreates shows up again on the next scan.
    private var deletedPaths: [String: Date] = [:]
    private static let tombstoneLifetime: TimeInterval = 120

    private init() {
        refreshAccess()
    }

    var showsPartialDiskData: Bool {
        !includesProtectedFolders
    }

    var hasSeenAccessOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func analyze() async {
        await performScan(quick: false, locksUI: true)
    }

    /// Refresh used right after a confirmed action batch. Skips the slow `du`
    /// collectors (space map, large consumers) so the list and counts update
    /// in a couple of seconds; the previous map rows are kept until the
    /// background pass replaces them.
    func refreshQuickly() async {
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
        demoMode = false
        refreshAccess()
        errorMessage = nil
        isScanning = true
        locksInteraction = locksUI

        if quick {
            status = "Refreshing after your changes…"
        } else if locksUI {
            status = "Scanning memory, processes, startup items, services, disk, caches and leftovers..."
        } else {
            status = "Refreshing the space map in the background…"
        }

        defer {
            scanInFlight = false
            isScanning = false
            locksInteraction = false
        }

        let startedAt = Date()
        var result = await ScanCoordinator.run(
            includeProtectedFolders: includesProtectedFolders,
            includeSlowCollectors: !quick
        )
        if quick, let current = report {
            result = result.mergingSlowItems(from: current)
        }
        result = result.removingItems(withIDs: [], paths: activeTombstones())

        report = result
        let duration = Date().timeIntervalSince(startedAt)
        lastDuration = duration
        status = String(
            format: "Found %d items in %.1fs. Nothing has been changed.",
            result.items.count,
            duration
        )
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
        if demoMode {
            accessStatus = .granted
            includesProtectedFolders = true
            return
        }

        accessStatus = FullDiskAccess.status()
        includesProtectedFolders = accessStatus == .granted || FullDiskAccess.allowsFolderPrompts
    }

    /// Shown once, the first time the dashboard opens. It is optional: the app
    /// already works without it and the user can dismiss it.
    func presentAccessSheetIfNeeded() {
        refreshAccess()

        guard !includesProtectedFolders, !hasSeenAccessOnboarding else { return }
        isAccessSheetPresented = true
    }

    func presentAccessSheet() {
        refreshAccess()
        isAccessSheetPresented = true
    }

    func skipAccess() {
        markOnboardingSeen()
        accessHint = nil
        isAccessSheetPresented = false
    }

    func markOnboardingSeen() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    func openFullDiskAccessSettings() {
        FullDiskAccess.openSettings()
        accessHint = "Enable SiftBar in the list, then click Check again. If it does not update, quit and reopen SiftBar."
    }

    func checkAccessAgain() {
        refreshAccess()

        if includesProtectedFolders {
            accessHint = nil
            markOnboardingSeen()
            isAccessSheetPresented = false
            Task { await analyze() }
        } else {
            accessHint = "Still off. After enabling it, you may need to quit and reopen SiftBar."
        }
    }

    func useFolderPrompts() {
        FullDiskAccess.setAllowsFolderPrompts(true)
        refreshAccess()
        accessHint = nil
        markOnboardingSeen()
        isAccessSheetPresented = false
        Task { await analyze() }
    }

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
        }
        purgeTombstones(now: now)
        guard let current = report else { return }
        report = current.removingItems(withIDs: ids, paths: paths)
    }
}
