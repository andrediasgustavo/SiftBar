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

    /// Folder names that belong to the Photos library. Walking them triggers
    /// the system photo-library permission prompt, which the disk map does not
    /// need, so they are measured only when the user grants access elsewhere.
    static let sensitiveLibraryNames: Set<String> = [
        "photos",
        "com.apple.photos",
        "com.apple.mobileslideshow"
    ]

    init(disk: DiskStats, includeProtectedFolders: Bool = true) {
        self.disk = disk
        self.includeProtectedFolders = includeProtectedFolders
    }

    struct Sizes: Sendable, Equatable {
        var home: [String: Int64]
        var library: [String: Int64]
        var applications: Int64
        var systemLibrary: Int64

        static let empty = Sizes(home: [:], library: [:], applications: 0, systemLibrary: 0)
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

        var measurements: [Measurement] = [
            Measurement(
                key: "appSupport",
                path: "\(home)/Library/Application Support",
                timeout: 25,
                include: true
            ),
            Measurement(
                key: "groupContainers",
                path: "\(home)/Library/Group Containers",
                timeout: 25,
                include: true
            ),
            Measurement(
                key: "caches",
                path: "\(home)/Library/Caches",
                timeout: 25,
                include: true
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
            excludingNames: Self.sensitiveLibraryNames,
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
            systemLibrary: values["systemLibrary"] ?? 0
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

    // MARK: - Grouping

    struct Category {
        let name: String
        let bytes: Int64
        let detail: String
        let evidence: [String]
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
            detail: "Xcode, Android SDK/emulator, Gradle and npm data.",
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
                detail: "Not measured by SiftBar: Pictures/Photos, macOS itself, /System, /private, snapshots, purgeable space and other volumes. SiftBar will not delete any of it.",
                evidence: ["total used - measured categories"]
            ))
        }

        let filtered = categories.filter { $0.bytes >= minimumBytes }
        let sorted = filtered.sorted { $0.bytes > $1.bytes }
        return Array(sorted.prefix(limit))
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
                isSlowRefresh: true
            )
        }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
