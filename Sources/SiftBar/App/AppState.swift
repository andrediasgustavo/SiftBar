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

    private init() {}

    func analyze() async {
        guard !isScanning else { return }

        isScanning = true
        errorMessage = nil
        status = "Scanning memory, processes, startup items, services, disk, caches and leftovers..."
        defer { isScanning = false }

        let startedAt = Date()
        let result = await ScanCoordinator.run()

        report = result
        lastDuration = Date().timeIntervalSince(startedAt)
        status = "Found \(result.items.count) items. Nothing has been changed."
    }

    func clearReport() {
        report = nil
        lastDuration = nil
        status = "Ready to analyze."
        errorMessage = nil
    }
}
