import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isScanning = false
    @Published private(set) var status = "Ready to analyze."
    @Published private(set) var report: ScanReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastDuration: TimeInterval?
    @Published private(set) var accessStatus: FullDiskAccess.Status = .unknown
    @Published private(set) var includesProtectedFolders = false
    @Published private(set) var accessHint: String?
    @Published var isAccessSheetPresented = false

    private let onboardingKey = "SiftBar.hasSeenAccessOnboarding"

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
        guard !isScanning else { return }

        refreshAccess()
        isScanning = true
        errorMessage = nil
        status = "Scanning memory, processes, startup items, services, disk, caches and leftovers..."
        defer { isScanning = false }

        let startedAt = Date()
        let result = await ScanCoordinator.run(
            includeProtectedFolders: includesProtectedFolders
        )

        report = result
        let duration = Date().timeIntervalSince(startedAt)
        lastDuration = duration
        status = String(
            format: "Found %d items in %.1fs. Nothing has been changed.",
            result.items.count,
            duration
        )
    }

    func refreshAccess() {
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

    func clearReport() {
        report = nil
        lastDuration = nil
        status = "Ready to analyze."
        errorMessage = nil
    }
}
