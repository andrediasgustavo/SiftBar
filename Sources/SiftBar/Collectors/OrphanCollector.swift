import Foundation

struct OrphanCollector: Collector {
    let category: ItemCategory = .leftovers

    static let minimumBytes: Int64 = 200 * 1024 * 1024
    static let limit = 10

    /// Apple/cloud folders that look like app names but are system data. They
    /// must never be offered as leftovers, even when no matching app exists.
    static let systemOwnedNames: Set<String> = [
        "clouddocs",
        "fileprovider",
        "knowledge",
        "callhistorydb",
        "addressbook",
        "calendars",
        "messages",
        "mail",
        "safari",
        "icloud",
        "ubiquity",
        "sharedfilelist",
        "dock",
        "spotlight",
        "homekit",
        "photos"
    ]

    struct Candidate: Sendable, Equatable {
        let name: String
        let path: String
        let confidence: LeftoverConfidence
        let confidenceReason: String?

        init(
            name: String,
            path: String,
            confidence: LeftoverConfidence = .high,
            confidenceReason: String? = nil
        ) {
            self.name = name
            self.path = path
            self.confidence = confidence
            self.confidenceReason = confidenceReason
        }
    }

    struct Measured: Sendable {
        let candidate: Candidate
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let supportPath = "\(home)/Library/Application Support"
        let inventory = await AppInventory.load()

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: supportPath) else {
            return []
        }

        let candidates = Self.candidates(
            entries: entries,
            inventory: inventory,
            supportPath: supportPath
        )

        var measured: [Measured] = []

        await withTaskGroup(of: Measured?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let bytes = await PathSizer.sizeInBytes(of: candidate.path),
                          bytes >= Self.minimumBytes else { return nil }
                    return Measured(candidate: candidate, bytes: bytes)
                }
            }

            for await result in group {
                if let result {
                    measured.append(result)
                }
            }
        }

        return Self.items(from: measured)
    }

    static func items(from measured: [Measured], limit: Int = OrphanCollector.limit) -> [ScanItem] {
        measured
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { item in
                let candidate = item.candidate
                let deviceText = "This folder can contain settings, history, saved games, or licenses, so it is not the same as a cache. Open it in Finder before deleting."

                let detail: String
                switch candidate.confidence {
                case .high:
                    detail = "No app named \(candidate.name) is installed in /Applications, ~/Applications, /System/Applications, Homebrew Caskroom, or Spotlight. \(deviceText)"
                case .medium:
                    detail = "SiftBar could not finish reading every app location, so \(candidate.name) may still belong to an installed app. \(deviceText)"
                case .low:
                    detail = "\(candidate.confidenceReason ?? "A vendor identifier matches this folder.") This folder may be shared by an app that is still installed, so SiftBar shows it for review only and will not move it to the Trash."
                }

                let warning: String
                switch candidate.confidence {
                case .high:
                    warning = "Review the contents first. This is app data, not recreatable cache."
                case .medium:
                    warning = "App inventory was incomplete. Confirm the app is really gone before removing this folder."
                case .low:
                    warning = "Low confidence: an installed app or receipt is related to this folder. SiftBar will not remove it."
                }

                return ScanItem(
                    category: .leftovers,
                    title: "Possible leftover: \(candidate.name)",
                    detail: detail,
                    impactLabel: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file),
                    impactBytes: item.bytes,
                    risk: .caution,
                    action: .trashLeftover(path: candidate.path, bytes: item.bytes),
                    evidence: candidate.path,
                    warning: warning,
                    isInformational: candidate.confidence == .low,
                    leftoverConfidence: candidate.confidence
                )
            }
    }

    /// Filters Application Support entries that look like they belong to an
    /// installed app. Hidden entries and Apple folders are never candidates.
    static func candidates(
        entries: [String],
        installed: [String],
        supportPath: String
    ) -> [Candidate] {
        let apps = installed.map {
            AppInventory.App(name: $0, path: "/Applications/\($0).app", source: .applications)
        }

        return candidates(
            entries: entries,
            inventory: AppInventory(
                apps: apps,
                receipts: [],
                caskTokens: [],
                isIncomplete: false
            ),
            supportPath: supportPath
        )
    }

    static func candidates(
        entries: [String],
        inventory: AppInventory,
        supportPath: String
    ) -> [Candidate] {
        entries
            .filter { !$0.hasPrefix(".") && !$0.lowercased().hasPrefix("com.apple.") }
            .filter { !isSystemOwned($0) }
            .compactMap { entry in
                switch inventory.ownership(for: entry) {
                case .owned:
                    return nil

                case .vendor:
                    let vendor = inventory.vendorIdentifier(for: entry)
                    let reason = vendor.map {
                        "A receipt or installed app uses the vendor identifier “\($0)”, so this may be shared vendor data rather than an orphan."
                    }
                    return Candidate(
                        name: entry,
                        path: "\(supportPath)/\(entry)",
                        confidence: .low,
                        confidenceReason: reason
                    )

                case .none:
                    let confidence: LeftoverConfidence = inventory.isIncomplete ? .medium : .high
                    return Candidate(
                        name: entry,
                        path: "\(supportPath)/\(entry)",
                        confidence: confidence,
                        confidenceReason: inventory.isIncomplete
                            ? "Some app locations could not be read during this scan."
                            : nil
                    )
                }
            }
    }

    static func isSystemOwned(_ entry: String) -> Bool {
        systemOwnedNames.contains(normalize(entry))
    }

    static func installedAppNames(
        directories: [String] = defaultAppDirectories(),
        fileManager: FileManager = .default
    ) -> [String] {
        AppInventory.scanStandardDirectories(directories: directories, fileManager: fileManager)
            .apps
            .map(\.name)
    }

    static func defaultAppDirectories() -> [String] {
        AppInventory.defaultAppDirectories()
    }

    static func hasMatchingApp(entry: String, installed: [String]) -> Bool {
        let needle = normalize(entry)
        // Very short folder names match too many apps; treat them as owned so
        // they are never reported as leftovers.
        guard needle.count >= 3 else { return true }

        return installed.contains { app in
            AppInventory.nameMatches(needle: needle, candidate: app)
        }
    }

    static func normalize(_ value: String) -> String {
        AppInventory.normalize(value)
    }
}
