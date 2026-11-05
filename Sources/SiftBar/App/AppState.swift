import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var isScanning = false
    @Published private(set) var status = "Ready to analyze."
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var errorMessage: String?

    private init() {}

    func analyze() async {
        guard !isScanning else { return }

        isScanning = true
        errorMessage = nil
        status = "Collecting system snapshot..."
        defer { isScanning = false }

        do {
            snapshot = try await SystemProbe.snapshot()
            status = "Phase 0 preview complete. Full analysis arrives in Phase 1."
        } catch {
            errorMessage = error.localizedDescription
            status = "Analysis failed."
        }
    }
}
