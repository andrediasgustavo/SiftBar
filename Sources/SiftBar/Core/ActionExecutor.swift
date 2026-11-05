import Darwin
import Foundation

struct ActionReport: Identifiable, Sendable {
    let id: UUID
    let title: String
    let success: Bool
    let message: String
    let reclaimedBytes: Int64

    init(item: ScanItem, success: Bool, message: String) {
        self.id = item.id
        self.title = item.title
        self.success = success
        self.message = message
        self.reclaimedBytes = success ? (item.impactBytes ?? 0) : 0
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

        case .stopService(let name):
            return "brew services stop \(name)"

        case .deletePath(let path, _):
            return "Move to Trash: \(path)"
        }
    }

    static func verb(for action: ItemAction) -> String {
        switch action {
        case .none: return "Change"
        case .killProcess: return "Quit"
        case .removeLoginItem: return "Remove"
        case .disableLaunchItem: return "Disable"
        case .stopService: return "Stop"
        case .deletePath: return "Move to Trash"
        }
    }

    static func title(for items: [ScanItem]) -> String {
        guard items.count == 1, let item = items.first else {
            return "Apply \(items.count) Actions…"
        }

        switch item.action {
        case .none: return "No Action"
        case .killProcess: return "Quit Process…"
        case .removeLoginItem: return "Remove Login Item…"
        case .disableLaunchItem: return "Disable Launch Item…"
        case .stopService: return "Stop Service…"
        case .deletePath: return "Move to Trash…"
        }
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

        case .deletePath(let path, _):
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
        if case .disableLaunchItem = action {
            return evidence.hasPrefix("/Library/")
        }
        return false
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

        case .disableLaunchItem(let label):
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
