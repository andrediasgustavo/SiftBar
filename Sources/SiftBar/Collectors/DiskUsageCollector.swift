import Foundation

/// Builds a coarse space map comparable to macOS System Settings without
/// walking the whole disk. It measures top-level entries of the home folder
/// and `~/Library` once, plus Applications and `/Library`, then derives the
/// remainder as "System & other".
struct DiskUsageCollector: Collector {
    let category: ItemCategory = .disk
    private let disk: DiskStats
    private let includeProtectedFolders: Bool

    static let minimumBytes: Int64 = 100 * 1024 * 1024
    static let limit = 12

    init(disk: DiskStats, includeProtectedFolders: Bool = true) {
        self.disk = disk
        self.includeProtectedFolders = includeProtectedFolders
    }

    struct Sizes: Sendable, Equatable {
        var home: [String: Int64]
        var library: [String: Int64]
        var applications: Int64
        var systemLibrary: Int64
        /// Categories measured inside the "System & other" remainder. They are
        /// shown as a read-only drill-down, never as cleanup actions.
        var remainderDetails: [RemainderDetail] = []
        /// Number of APFS local snapshots, when `tmutil` reports them. The
        /// bytes are managed by macOS and are not sized by SiftBar.
        var snapshotCount: Int = 0

        static let empty = Sizes(home: [:], library: [:], applications: 0, systemLibrary: 0)
    }

    /// One named part of "System & other". Every entry is measured with `du`
    /// on a path that is not already counted by another category.
    struct RemainderDetail: Sendable, Equatable {
        let name: String
        let bytes: Int64
        let detail: String
        let evidence: String
        let revealPath: String?
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // The space map touches many large trees. Running every `du` at once
        // makes the whole Mac sluggish during the scan, so measurements are
        // grouped in bounded chunks below.
        struct Measurement: Sendable {
            let key: String
            let path: String
            let timeout: TimeInterval
            let include: Bool
            let ignoring: [String]

            init(
                key: String,
                path: String,
                timeout: TimeInterval,
                include: Bool,
                ignoring: [String] = []
            ) {
                self.key = key
                self.path = path
                self.timeout = timeout
                self.include = include
                self.ignoring = ignoring
            }
        }

        let measurements: [Measurement] = [
            Measurement(
                key: "appSupport",
                path: "\(home)/Library/Application Support",
                timeout: 25,
                include: true,
                ignoring: SensitivePaths.duIgnoreNames
            ),
            Measurement(
                key: "groupContainers",
                path: "\(home)/Library/Group Containers",
                timeout: 25,
                include: true,
                ignoring: SensitivePaths.duIgnoreNames
            ),
            Measurement(
                key: "caches",
                path: "\(home)/Library/Caches",
                timeout: 25,
                include: true,
                ignoring: SensitivePaths.duIgnoreNames
            ),
            Measurement(
                key: "developerLibrary",
                path: "\(home)/Library/Developer",
                timeout: 20,
                include: true
            ),
            Measurement(
                key: "androidLibrary",
                path: "\(home)/Library/Android",
                timeout: 20,
                include: true
            ),
            Measurement(
                key: "mobileDocuments",
                path: "\(home)/Library/Mobile Documents",
                timeout: 25,
                include: true
            ),
            Measurement(key: "applications", path: "/Applications", timeout: 30, include: true),
            Measurement(
                key: "userApplications",
                path: "\(home)/Applications",
                timeout: 10,
                include: true
            ),
            // Xcode's simulator runtimes alone can be tens of GB and walking
            // them takes far longer than the rest of /Library (30s+ on a Mac
            // with several runtimes installed). Exclude the developer
            // toolchain: those bytes stay in the "System & other" remainder,
            // and the simulator caches are listed separately by the Caches
            // tab.
            Measurement(
                key: "systemLibrary",
                path: "/Library",
                timeout: 12,
                include: true,
                ignoring: ["Developer"]
            ),
            Measurement(key: "android", path: "\(home)/.android", timeout: 15, include: true),
            Measurement(key: "gradle", path: "\(home)/.gradle", timeout: 15, include: true),
            Measurement(key: "npm", path: "\(home)/.npm", timeout: 15, include: true),
            // Named parts of the remainder. None of these paths is inside a
            // category measured above, so they do not double count.
            Measurement(key: "trash", path: "\(home)/.Trash", timeout: 10, include: true),
            Measurement(
                key: "vmSwap",
                path: "/private/var/vm",
                timeout: 10,
                include: true
            ),
            Measurement(
                key: "homebrew",
                path: "/opt/homebrew",
                timeout: 20,
                include: true,
                ignoring: ["Caskroom"]
            ),
            Measurement(
                key: "homebrewIntel",
                path: "/usr/local/Cellar",
                timeout: 20,
                include: true
            ),
            Measurement(
                key: "cloudStorage",
                path: "\(home)/Library/CloudStorage",
                timeout: 20,
                include: true
            ),
            // TCC-protected folders are opt-in. When disabled they are skipped
            // without spawning a process (the child task returns zero).
            Measurement(
                key: "documents",
                path: "\(home)/Documents",
                timeout: 20,
                include: includeProtectedFolders
            ),
            Measurement(
                key: "desktop",
                path: "\(home)/Desktop",
                timeout: 20,
                include: includeProtectedFolders
            ),
            Measurement(
                key: "downloads",
                path: "\(home)/Downloads",
                timeout: 20,
                include: includeProtectedFolders
            )
        ]

        // Containers are measured with a single `du -d 1` instead of one
        // process per container, which could be hundreds.
        async let containerSizesTask = PathSizer.childDirectorySizes(
            of: "\(home)/Library/Containers",
            excludingNames: SensitivePaths.mediaNames,
            ignoringNames: SensitivePaths.duIgnoreNames,
            timeout: 20
        )

        var values: [String: Int64] = [:]
        for chunk in Self.chunks(measurements, size: Self.maxConcurrentMeasurements) {
            await withTaskGroup(of: (String, Int64).self) { group in
                for measurement in chunk {
                    group.addTask {
                        guard measurement.include else { return (measurement.key, 0) }
                        let bytes = await PathSizer.sizeInBytes(
                            of: measurement.path,
                            timeout: measurement.timeout,
                            ignoringNames: measurement.ignoring
                        ) ?? 0
                        return (measurement.key, bytes)
                    }
                }

                for await (key, bytes) in group {
                    values[key] = bytes
                }
            }
        }

        let containerSizes = await containerSizesTask
        let containersBytes = containerSizes.reduce(Int64(0)) { $0 + $1.bytes }
        let snapshotCount = await Self.localSnapshotCount()

        let homeSizes: [String: Int64] = [
            "Documents": values["documents"] ?? 0,
            "Desktop": values["desktop"] ?? 0,
            "Downloads": values["downloads"] ?? 0,
            ".android": values["android"] ?? 0,
            ".gradle": values["gradle"] ?? 0,
            ".npm": values["npm"] ?? 0
        ]

        let librarySizes: [String: Int64] = [
            "Application Support": values["appSupport"] ?? 0,
            "Containers": containersBytes,
            "Group Containers": values["groupContainers"] ?? 0,
            "Caches": values["caches"] ?? 0,
            "Developer": values["developerLibrary"] ?? 0,
            "Android": values["androidLibrary"] ?? 0,
            "Mobile Documents": values["mobileDocuments"] ?? 0
        ]

        let sizes = Sizes(
            home: homeSizes,
            library: librarySizes,
            applications: (values["applications"] ?? 0) + (values["userApplications"] ?? 0),
            systemLibrary: values["systemLibrary"] ?? 0,
            remainderDetails: Self.remainderDetails(from: values, snapshotCount: snapshotCount),
            snapshotCount: snapshotCount
        )

        guard sizes != .empty else { return [] }
        return Self.items(sizes: sizes, disk: disk)
    }

    /// Number of `du` walks allowed to run at the same time.
    static let maxConcurrentMeasurements = 7

    /// Splits values into chunks so each task group stays bounded.
    static func chunks<T>(_ values: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [values] }

        var result: [[T]] = []
        var index = 0
        while index < values.count {
            let end = min(index + size, values.count)
            result.append(Array(values[index..<end]))
            index = end
        }
        return result
    }

    /// Skips TCC-protected home folders when the user has not granted Full
    /// Disk Access (and has not opted into folder-by-folder prompts).
    static func optionalSize(
        of path: String,
        include: Bool,
        timeout: TimeInterval
    ) async -> Int64? {
        guard include else { return nil }
        return await PathSizer.sizeInBytes(of: path, timeout: timeout)
    }

    static func localSnapshotCount() async -> Int {
        guard let result = try? await CommandRunner.run(
            "/usr/bin/tmutil",
            arguments: ["listlocalsnapshots", "/"],
            timeout: 5
        ), result.exitCode == 0 else {
            return 0
        }

        return result.stdout
            .split(separator: "\n")
            .filter { $0.contains("com.apple.TimeMachine") || $0.hasSuffix(".local") }
            .count
    }

    /// Builds the named parts of the remainder. Paths are chosen so they are
    /// not already inside a measured category (otherwise the drill-down would
    /// double count). Sizes are still estimates: APFS can share blocks between
    /// folders, so the UI treats them as approximate.
    static func remainderDetails(
        from values: [String: Int64],
        snapshotCount: Int
    ) -> [RemainderDetail] {
        let details: [RemainderDetail] = [
            RemainderDetail(
                name: "Trash",
                bytes: values["trash"] ?? 0,
                detail: "Files you deleted that still take space until the Trash is emptied. SiftBar does not empty it.",
                evidence: "du -sk ~/.Trash",
                revealPath: "~/.Trash"
            ),
            RemainderDetail(
                name: "Swap files",
                bytes: values["vmSwap"] ?? 0,
                detail: "RAM that macOS paged to disk. The system grows and shrinks these files by itself.",
                evidence: "du -sk /private/var/vm",
                revealPath: nil
            ),
            RemainderDetail(
                name: "Homebrew",
                bytes: values["homebrew"] ?? 0,
                detail: "Homebrew packages and Cellar on Apple Silicon. Installed app bundles are counted under Applications; Caskroom is excluded here.",
                evidence: "du -sk -I Caskroom /opt/homebrew",
                revealPath: "/opt/homebrew"
            ),
            RemainderDetail(
                name: "Homebrew (Intel)",
                bytes: values["homebrewIntel"] ?? 0,
                detail: "Homebrew Cellar under /usr/local.",
                evidence: "du -sk /usr/local/Cellar",
                revealPath: "/usr/local/Cellar"
            ),
            RemainderDetail(
                name: "Cloud storage",
                bytes: values["cloudStorage"] ?? 0,
                detail: "Dropbox, OneDrive, Google Drive and other File Provider folders. This is your data, not cache.",
                evidence: "du -sk ~/Library/CloudStorage",
                revealPath: "~/Library/CloudStorage"
            )
        ]

        var measured = details.filter { $0.bytes > 0 }

        if snapshotCount > 0 {
            measured.append(RemainderDetail(
                name: "Local snapshots",
                bytes: 0,
                detail: "\(snapshotCount) APFS local \(snapshotCount == 1 ? "snapshot" : "snapshots"). macOS creates and removes them automatically; SiftBar cannot size or delete them.",
                evidence: "tmutil listlocalsnapshots /",
                revealPath: nil
            ))
        }

        return measured
    }

    // MARK: - Grouping

    struct Category {
        let name: String
        let bytes: Int64
        let detail: String
        let evidence: [String]
        /// Read-only rows shown when the user expands "System & other".
        var children: [ScanItem] = []
    }

    /// Pure builder so the grouping and remainder logic can be tested without
    /// touching the file system.
    static func categories(sizes: Sizes, disk: DiskStats) -> [Category] {
        let home = sizes.home
        let library = sizes.library

        let content: [(name: String, path: String)] = [
            (name: "Desktop", path: "~/Desktop"),
            (name: "Documents", path: "~/Documents"),
            (name: "Downloads", path: "~/Downloads")
        ]

        let contentBytes = sum(content.map { home[$0.name] ?? 0 })
        let developerBytes = sum([
            library["Developer"] ?? 0,
            library["Android"] ?? 0,
            home[".android"] ?? 0,
            home[".gradle"] ?? 0,
            home[".npm"] ?? 0
        ])
        let appDataBytes = sum([
            library["Application Support"] ?? 0,
            library["Containers"] ?? 0,
            library["Group Containers"] ?? 0
        ])
        let cachesBytes: Int64 = library["Caches"] ?? 0
        let iCloudBytes: Int64 = library["Mobile Documents"] ?? 0

        var knownHome = content.map { $0.name }
        knownHome.append(contentsOf: [
            "Library", ".android", ".gradle", ".npm", ".cache", ".cargo", ".rustup"
        ])
        let knownHomeSet = Set(knownHome)

        var otherHomeBytes: Int64 = 0
        for (name, bytes) in home where !knownHomeSet.contains(name) && !name.hasPrefix(".") {
            otherHomeBytes += bytes
        }

        var categories: [Category] = []
        categories.append(Category(
            name: "Applications",
            bytes: sizes.applications,
            detail: "App bundles in /Applications and ~/Applications.",
            evidence: ["du -sk /Applications", "du -sk ~/Applications"]
        ))
        categories.append(Category(
            name: "Documents & media",
            bytes: contentBytes,
            detail: "Desktop, Documents and Downloads.",
            evidence: content.map { "du -sk \($0.path)" }
        ))
        categories.append(Category(
            name: "Developer",
            bytes: developerBytes,
            detail: "Xcode data in your home folder, Android SDK/emulator, Gradle and npm.",
            evidence: ["du -sk ~/Library/Developer", "du -sk ~/Library/Android"]
        ))
        categories.append(Category(
            name: "App data",
            bytes: appDataBytes,
            detail: "Application Support, Containers and Group Containers. This is app data, not cache.",
            evidence: ["du -sk ~/Library/Application Support", "du -sk ~/Library/Containers"]
        ))
        categories.append(Category(
            name: "Caches",
            bytes: cachesBytes,
            detail: "Recreatable caches. The Caches tab lists what SiftBar can move to the Trash.",
            evidence: ["du -sk ~/Library/Caches"]
        ))
        categories.append(Category(
            name: "iCloud Drive",
            bytes: iCloudBytes,
            detail: "Files stored in iCloud Drive and downloaded to this Mac.",
            evidence: ["du -sk ~/Library/Mobile Documents"]
        ))
        categories.append(Category(
            name: "Other user folders",
            bytes: otherHomeBytes,
            detail: "Other folders directly in your home folder, such as project folders.",
            evidence: ["du -d 1 -k ~"]
        ))
        categories.append(Category(
            name: "System-wide data",
            bytes: sizes.systemLibrary,
            detail: "Support files and caches installed in /Library. Developer tooling (Xcode simulators) is measured separately by the Caches tab and stays in System & other.",
            evidence: ["du -sk -I Developer /Library"]
        ))

        let measured = sum(categories.map { $0.bytes })
        let remainder = max(0, disk.usedBytes - measured)
        if remainder > 0 {
            categories.append(Category(
                name: "System & other",
                bytes: remainder,
                detail: "Not measured by the main map: macOS itself, /System, /private, protected folders, purgeable space and other volumes. Expand it to see the parts SiftBar can name, including what still cannot be measured. SiftBar will not delete any of it.",
                evidence: ["total used - measured categories"],
                children: remainderChildren(
                    details: sizes.remainderDetails,
                    remainder: remainder
                )
            ))
        }

        let filtered = categories.filter { $0.bytes >= minimumBytes }
        let sorted = filtered.sorted { $0.bytes > $1.bytes }
        return Array(sorted.prefix(limit))
    }

    /// Splits the remainder into named rows without ever claiming more bytes
    /// than the remainder itself. A category that does not fit (APFS block
    /// sharing can make folder sums exceed the volume total) is left in the
    /// unaccounted row instead of inflating the total.
    static func remainderChildren(details: [RemainderDetail], remainder: Int64) -> [ScanItem] {
        var budget = max(0, remainder)
        var children: [ScanItem] = []

        for detail in details.sorted(by: { $0.bytes > $1.bytes }) {
            if detail.bytes > 0 {
                guard detail.bytes >= minimumBytes, detail.bytes <= budget else { continue }
                budget -= detail.bytes
            }

            let isManaged = detail.bytes == 0
            children.append(ScanItem(
                category: .disk,
                title: detail.name,
                detail: detail.detail,
                impactLabel: isManaged ? "macOS-managed" : format(detail.bytes),
                impactBytes: isManaged ? nil : detail.bytes,
                risk: .safe,
                action: .none,
                evidence: detail.evidence,
                isInformational: true,
                isBreakdown: true,
                isSlowRefresh: true,
                revealPath: detail.revealPath
            ))
        }

        if budget > 0 {
            children.append(ScanItem(
                category: .disk,
                title: "Other macOS and protected data",
                detail: "macOS itself, /System, /private, protected folders, purgeable space and other volumes. SiftBar cannot measure or clean it.",
                impactLabel: format(budget),
                impactBytes: budget,
                risk: .safe,
                action: .none,
                evidence: "used - measured - named categories",
                isInformational: true,
                isBreakdown: true,
                isSlowRefresh: true
            ))
        }

        return children
    }

    private static func sum(_ values: [Int64]) -> Int64 {
        values.reduce(0, +)
    }

    static func items(sizes: Sizes, disk: DiskStats) -> [ScanItem] {
        categories(sizes: sizes, disk: disk).map { category in
            ScanItem(
                category: .disk,
                title: category.name,
                detail: "\(format(category.bytes)). \(category.detail)",
                impactLabel: format(category.bytes),
                impactBytes: category.bytes,
                risk: .safe,
                action: .none,
                evidence: category.evidence.joined(separator: " · "),
                isInformational: true,
                isBreakdown: true,
                isSlowRefresh: true,
                children: category.children
            )
        }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
