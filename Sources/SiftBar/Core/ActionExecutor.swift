import Darwin
import Foundation

struct ActionReport: Identifiable, Sendable {
    let id: UUID
    let title: String
    let success: Bool
    let message: String
    let reclaimedBytes: Int64
    let domain: ReclaimDomain?
    let movedToTrash: Bool

    init(item: ScanItem, success: Bool, message: String) {
        self.id = item.id
        self.title = item.title
        self.success = success
        self.message = message
        self.reclaimedBytes = success ? (item.impactBytes ?? 0) : 0
        self.domain = item.reclaimDomain
        self.movedToTrash = {
            switch item.action {
            case .deletePath, .trashLeftover: return true
            default: return false
            }
        }()
    }
}

/// Executes the actions attached to review items. Every call goes through
/// `CommandRunner`, which launches executables without a shell, so no item
/// text can be interpreted as a command.
enum ActionExecutor {
    static func preview(for action: ItemAction) -> String {
        switch action {
        case .none:
            return "No action"

        case .killProcess(let pid, let name):
            return "kill -TERM \(pid)    # \(name)"

        case .removeLoginItem(let name):
            return "Remove login item: \(name)"

        case .disableLaunchItem(let label):
            let domain = "gui/\(getuid())"
            return "launchctl bootout \(domain)/\(label)\nlaunchctl disable \(domain)/\(label)"

        case .enableLaunchItem(let label):
            let domain = "gui/\(getuid())"
            return "launchctl enable \(domain)/\(label)"

        case .stopService(let name):
            return "brew services stop \(name)"

        case .deletePath(let path, _):
            return "Move to Trash: \(path)"

        case .trashLeftover(let path, _):
            return "Move leftover app data to Trash: \(path)"
        }
    }

    /// Item-aware preview. Enabling a launch item can also bootstrap its plist,
    /// so show the real path when the file exists.
    static func preview(for item: ScanItem) -> String {
        guard case .enableLaunchItem(let label) = item.action else {
            return preview(for: item.action)
        }

        let domain = "gui/\(getuid())"
        var lines = ["launchctl enable \(domain)/\(label)"]

        if item.evidence.hasPrefix("/") {
            let plist = URL(fileURLWithPath: item.evidence)
                .appendingPathComponent("\(label).plist")

            if FileManager.default.fileExists(atPath: plist.path) {
                lines.append("launchctl bootstrap \(domain) \(plist.path)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func verb(for action: ItemAction) -> String {
        switch action {
        case .none: return "Change"
        case .killProcess: return "Quit"
        case .removeLoginItem: return "Remove"
        case .disableLaunchItem: return "Disable"
        case .enableLaunchItem: return "Enable"
        case .stopService: return "Stop"
        case .deletePath: return "Move to Trash"
        case .trashLeftover: return "Move to Trash"
        }
    }

    static func title(for items: [ScanItem]) -> String {
        guard !items.isEmpty else { return "Apply Actions…" }

        if items.count == 1, let item = items.first {
            switch item.action {
            case .none: return "No Action"
            case .killProcess: return "Quit Process…"
            case .removeLoginItem: return "Remove Login Item…"
            case .disableLaunchItem: return "Disable Launch Item…"
            case .enableLaunchItem: return "Enable Launch Item…"
            case .stopService: return "Stop Service…"
            case .deletePath: return "Move to Trash…"
            case .trashLeftover: return "Move Leftover to Trash…"
            }
        }

        return batchTitle(for: items, suffix: "…")
    }

    /// Same verb as the action bar, without the ellipsis used when a sheet
    /// will follow. Mixed batches fall back to a neutral title.
    static func confirmTitle(for items: [ScanItem]) -> String {
        batchTitle(for: items, suffix: "")
    }

    private static func batchTitle(for items: [ScanItem], suffix: String) -> String {
        let count = items.count
        let actions = items.map(\.action)

        if actions.allSatisfy({ if case .killProcess = $0 { return true }; return false }) {
            return "Quit \(count) Processes\(suffix)"
        }
        if actions.allSatisfy({ if case .deletePath = $0 { return true }; return false }) {
            return "Move \(count) to Trash\(suffix)"
        }
        if actions.allSatisfy({ if case .trashLeftover = $0 { return true }; return false }) {
            return "Move \(count) Leftovers to Trash\(suffix)"
        }
        if actions.allSatisfy({ if case .disableLaunchItem = $0 { return true }; return false }) {
            return "Disable \(count) Launch Items\(suffix)"
        }
        if actions.allSatisfy({ if case .enableLaunchItem = $0 { return true }; return false }) {
            return "Enable \(count) Launch Items\(suffix)"
        }
        if actions.allSatisfy({ if case .stopService = $0 { return true }; return false }) {
            return "Stop \(count) Services\(suffix)"
        }

        return "Apply \(count) Actions\(suffix)"
    }

    static func sheetTitle(for items: [ScanItem]) -> String {
        items.count == 1 ? "Review 1 Action" : "Review \(items.count) Actions"
    }

    static func perform(_ item: ScanItem) async -> ActionReport {
        switch item.action {
        case .none:
            return ActionReport(item: item, success: false, message: "This item has no action.")

        case .killProcess(let pid, let name):
            return await run(
                item,
                executable: "/bin/kill",
                arguments: ["-TERM", String(pid)],
                successMessage: "Quit \(name)."
            )

        case .disableLaunchItem(let label):
            let domain = "gui/\(getuid())"

            // `bootout` fails when the item is not currently loaded; that is
            // fine, the `disable` below is what prevents it from loading again.
            _ = try? await CommandRunner.run(
                "/bin/launchctl",
                arguments: ["bootout", "\(domain)/\(label)"],
                timeout: 10
            )

            return await run(
                item,
                executable: "/bin/launchctl",
                arguments: ["disable", "\(domain)/\(label)"],
                successMessage: "Disabled \(label)."
            )

        case .stopService(let name):
            guard let brew = brewPath() else {
                return ActionReport(item: item, success: false, message: "Homebrew was not found.")
            }

            return await run(
                item,
                executable: brew,
                arguments: ["services", "stop", name],
                timeout: 30,
                successMessage: "Stopped \(name)."
            )

        case .enableLaunchItem(let label):
            let domain = "gui/\(getuid())"

            let enabled = await run(
                item,
                executable: "/bin/launchctl",
                arguments: ["enable", "\(domain)/\(label)"],
                successMessage: "Enabled \(label)."
            )
            guard enabled.success else { return enabled }

            // Load the agent immediately when the plist is still on disk.
            if item.evidence.hasPrefix("/") {
                let plist = URL(fileURLWithPath: item.evidence)
                    .appendingPathComponent("\(label).plist")

                if FileManager.default.fileExists(atPath: plist.path) {
                    _ = try? await CommandRunner.run(
                        "/bin/launchctl",
                        arguments: ["bootstrap", domain, plist.path],
                        timeout: 10
                    )
                }
            }

            return enabled

        case .deletePath(let path, _):
            // Defense in depth: even if an item was forged or a collector
            // regresses, only known cache roots can be moved to the Trash.
            guard CleanupWhitelist.allows(path) else {
                return ActionReport(
                    item: item,
                    success: false,
                    message: "Refused: \(path) is outside the cleanup whitelist."
                )
            }

            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(
                        at: URL(fileURLWithPath: path),
                        resultingItemURL: nil
                    )
                }.value

                return ActionReport(item: item, success: true, message: "Moved to Trash: \(path)")
            } catch {
                return ActionReport(item: item, success: false, message: error.localizedDescription)
            }

        case .trashLeftover(let path, _):
            guard CleanupWhitelist.allowsLeftover(path) else {
                return ActionReport(
                    item: item,
                    success: false,
                    message: "Refused: \(path) is not a top-level Application Support folder."
                )
            }

            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(
                        at: URL(fileURLWithPath: path),
                        resultingItemURL: nil
                    )
                }.value

                return ActionReport(
                    item: item,
                    success: true,
                    message: "Moved to Trash: \(path). Empty the Trash to free the space."
                )
            } catch {
                return ActionReport(item: item, success: false, message: error.localizedDescription)
            }

        case .removeLoginItem(let name):
            return ActionReport(
                item: item,
                success: false,
                message: "Removing \(name) is not supported yet."
            )
        }
    }

    private static func run(
        _ item: ScanItem,
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 10,
        successMessage: String
    ) async -> ActionReport {
        do {
            let result = try await CommandRunner.run(executable, arguments: arguments, timeout: timeout)

            if result.exitCode == 0 {
                return ActionReport(item: item, success: true, message: successMessage)
            }

            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ActionReport(
                item: item,
                success: false,
                message: stderr.isEmpty ? "Exited with code \(result.exitCode)." : stderr
            )
        } catch {
            return ActionReport(item: item, success: false, message: error.localizedDescription)
        }
    }

    private static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

extension ScanItem {
    /// System-wide launch items need admin rights. SiftBar does not request
    /// privileges, so it shows them but refuses to change them.
    var requiresAdmin: Bool {
        switch action {
        case .disableLaunchItem, .enableLaunchItem:
            return evidence.hasPrefix("/Library/")
        case .deletePath(let path, _):
            // System-wide caches need admin rights too. Phase 5 is deferred, so
            // lock them instead of letting a doomed action run without sudo.
            return path.hasPrefix("/Library/")
        case .trashLeftover:
            return false
        default:
            return false
        }
    }

    var canBeChanged: Bool {
        isActionable && !requiresAdmin
    }

    /// A real filesystem location for the row, when there is one. Cache and
    /// leftover items have exact paths; launch items resolve to their plist.
    var revealURL: URL? {
        let fileManager = FileManager.default

        switch action {
        case .deletePath(let path, _):
            return URL(fileURLWithPath: path)

        case .trashLeftover(let path, _):
            return URL(fileURLWithPath: path)

        case .disableLaunchItem(let label), .enableLaunchItem(let label):
            guard evidence.hasPrefix("/") else { return nil }
            let directory = URL(fileURLWithPath: evidence)
            let plist = directory.appendingPathComponent("\(label).plist")
            return fileManager.fileExists(atPath: plist.path) ? plist : directory

        default:
            guard evidence.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: evidence)
        }
    }
}
