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

        // Measure only directory totals. Scanning all of `~` or `~/Library`
        // also traverses Photos/TCC-protected folders and triggers permission
        // prompts for data the space map does not need.
        async let appSupport = PathSizer.sizeInBytes(of: "\(home)/Library/Application Support", timeout: 25)
        async let containers = PathSizer.sizesOfChildren(
            of: "\(home)/Library/Containers",
            excludingNames: Self.sensitiveLibraryNames,
            timeout: 20
        )
        async let groupContainers = PathSizer.sizeInBytes(of: "\(home)/Library/Group Containers", timeout: 25)
        async let caches = PathSizer.sizeInBytes(of: "\(home)/Library/Caches", timeout: 25)
        async let developerLibrary = PathSizer.sizeInBytes(of: "\(home)/Library/Developer", timeout: 20)
        async let androidLibrary = PathSizer.sizeInBytes(of: "\(home)/Library/Android", timeout: 20)
        async let mobileDocuments = PathSizer.sizeInBytes(of: "\(home)/Library/Mobile Documents", timeout: 25)

        async let applications = PathSizer.sizeInBytes(of: "/Applications", timeout: 30)
        async let userApplications = PathSizer.sizeInBytes(of: "\(home)/Applications", timeout: 10)
        async let systemLibrary = PathSizer.sizeInBytes(of: "/Library", timeout: 30)

        async let documents = Self.optionalSize(
            of: "\(home)/Documents",
            include: includeProtectedFolders,
            timeout: 20
        )
        async let desktop = Self.optionalSize(
            of: "\(home)/Desktop",
            include: includeProtectedFolders,
            timeout: 20
        )
        async let downloads = Self.optionalSize(
            of: "\(home)/Downloads",
            include: includeProtectedFolders,
            timeout: 20
        )

        async let android = PathSizer.sizeInBytes(of: "\(home)/.android", timeout: 15)
        async let gradle = PathSizer.sizeInBytes(of: "\(home)/.gradle", timeout: 15)
        async let npm = PathSizer.sizeInBytes(of: "\(home)/.npm", timeout: 15)

        let homeSizes: [String: Int64] = [
            "Documents": await documents ?? 0,
            "Desktop": await desktop ?? 0,
            "Downloads": await downloads ?? 0,
            ".android": await android ?? 0,
            ".gradle": await gradle ?? 0,
            ".npm": await npm ?? 0
        ]

        let librarySizes: [String: Int64] = [
            "Application Support": await appSupport ?? 0,
            "Containers": await containers,
            "Group Containers": await groupContainers ?? 0,
            "Caches": await caches ?? 0,
            "Developer": await developerLibrary ?? 0,
            "Android": await androidLibrary ?? 0,
            "Mobile Documents": await mobileDocuments ?? 0
        ]

        let sizes = Sizes(
            home: homeSizes,
            library: librarySizes,
            applications: (await applications ?? 0) + (await userApplications ?? 0),
            systemLibrary: await systemLibrary ?? 0
        )

        guard sizes != .empty else { return [] }
        return Self.items(sizes: sizes, disk: disk)
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

        let content: [(String, String)] = [
            ("Desktop", "~/Desktop"),
            ("Documents", "~/Documents"),
            ("Downloads", "~/Downloads")
        ]

        let contentBytes = content.reduce(Int64(0)) { $0 + (home[$1.0] ?? 0) }

        let developerBytes =
            (library["Developer"] ?? 0)
            + (library["Android"] ?? 0)
            + (home[".android"] ?? 0)
            + (home[".gradle"] ?? 0)
            + (home[".npm"] ?? 0)

        let appDataBytes =
            (library["Application Support"] ?? 0)
            + (library["Containers"] ?? 0)
            + (library["Group Containers"] ?? 0)

        let cachesBytes = library["Caches"] ?? 0
        let iCloudBytes = library["Mobile Documents"] ?? 0

        let knownHome: Set<String> = Set(
            content.map(\.0)
                + ["Library", ".android", ".gradle", ".npm"]
                + [".cache", ".cargo", ".rustup"]
        )
        let otherHomeBytes = home
            .filter { !knownHome.contains($0.key) && !$0.key.hasPrefix(".") }
            .reduce(Int64(0)) { $0 + $1.value }

        var categories: [Category] = [
            Category(
                name: "Applications",
                bytes: sizes.applications,
                detail: "App bundles in /Applications and ~/Applications.",
                evidence: ["du -sk /Applications", "du -sk ~/Applications"]
            ),
            Category(
                name: "Documents & media",
                bytes: contentBytes,
                detail: "Desktop, Documents and Downloads.",
                evidence: content.map { "du -sk \($0.1)" }
            ),
            Category(
                name: "Developer",
                bytes: developerBytes,
                detail: "Xcode, Android SDK/emulator, Gradle and npm data.",
                evidence: ["du -sk ~/Library/Developer", "du -sk ~/Library/Android"]
            ),
            Category(
                name: "App data",
                bytes: appDataBytes,
                detail: "Application Support, Containers and Group Containers. This is app data, not cache.",
                evidence: ["du -sk ~/Library/Application Support", "du -sk ~/Library/Containers"]
            ),
            Category(
                name: "Caches",
                bytes: cachesBytes,
                detail: "Recreatable caches. The Caches tab lists what SiftBar can move to the Trash.",
                evidence: ["du -sk ~/Library/Caches"]
            ),
            Category(
                name: "iCloud Drive",
                bytes: iCloudBytes,
                detail: "Files stored in iCloud Drive and downloaded to this Mac.",
                evidence: ["du -sk ~/Library/Mobile Documents"]
            ),
            Category(
                name: "Other user folders",
                bytes: otherHomeBytes,
                detail: "Other folders directly in your home folder, such as project folders.",
                evidence: ["du -d 1 -k ~"]
            ),
            Category(
                name: "System-wide data",
                bytes: sizes.systemLibrary,
                detail: "Support files and caches installed in /Library.",
                evidence: ["du -d 1 -k /Library"]
            )
        ]

        let measured = categories.reduce(Int64(0)) { $0 + $1.bytes }
        let remainder = max(0, disk.usedBytes - measured)
        if remainder > 0 {
            categories.append(Category(
                name: "System & other",
                bytes: remainder,
                detail: "Not measured by SiftBar: Pictures/Photos, macOS itself, /System, /private, snapshots, purgeable space and other volumes. SiftBar will not delete any of it.",
                evidence: ["total used - measured categories"]
            ))
        }

        return categories
            .filter { $0.bytes >= minimumBytes }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { $0 }
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
                isBreakdown: true
            )
        }
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
