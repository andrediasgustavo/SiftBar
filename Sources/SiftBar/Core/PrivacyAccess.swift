import AppKit
import Foundation

/// macOS grants access folder by folder for Desktop, Documents and Downloads.
/// There is no API to combine those prompts. Full Disk Access is the single
/// consent that covers all of them, so SiftBar asks for it once and otherwise
/// avoids touching protected folders.
enum FullDiskAccess {
    enum Status: String, Sendable {
        case granted
        case denied
        case unknown
    }

    struct Probe: Sendable, Equatable {
        let path: String
        let isDirectory: Bool

        init(path: String, isDirectory: Bool = false) {
            self.path = path
            self.isDirectory = isDirectory
        }
    }

    static let allowFolderPromptsKey = "SiftBar.allowFolderPrompts"

    static var allowsFolderPrompts: Bool {
        UserDefaults.standard.bool(forKey: allowFolderPromptsKey)
    }

    static func setAllowsFolderPrompts(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: allowFolderPromptsKey)
    }

    /// The default probes are files/folders that macOS protects with Full Disk
    /// Access. Reading them does not trigger a prompt; it just fails when the
    /// permission is off.
    static func status() -> Status {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return status(probes: [
            // Present on every Mac. It is protected by TCC/SIP and normally
            // readable only with Full Disk Access.
            Probe(path: "/Library/Application Support/com.apple.TCC/TCC.db"),
            Probe(path: "\(home)/Library/Safari/History.db"),
            Probe(path: "\(home)/Library/Messages/chat.db"),
            Probe(path: "\(home)/Library/Mail", isDirectory: true),
            Probe(path: "\(home)/Library/CallHistoryDB/CallHistory.storedata")
        ])
    }

    static func status(
        probes: [Probe],
        fileManager: FileManager = .default
    ) -> Status {
        var sawExisting = false

        for probe in probes {
            guard fileManager.fileExists(atPath: probe.path) else { continue }
            sawExisting = true

            if canRead(probe, fileManager: fileManager) {
                return .granted
            }
        }

        return sawExisting ? .denied : .unknown
    }

    static func canRead(_ probe: Probe, fileManager: FileManager = .default) -> Bool {
        if probe.isDirectory {
            return (try? fileManager.contentsOfDirectory(atPath: probe.path)) != nil
        }

        guard let handle = FileHandle(forReadingAtPath: probe.path) else {
            return false
        }

        handle.closeFile()
        return true
    }

    /// Deep-links to Privacy & Security → Full Disk Access. The URL changed
    /// across macOS releases, so try the modern one first.
    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}
