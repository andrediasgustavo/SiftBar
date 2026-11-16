import Foundation

/// Catalog of installed app bundles, Homebrew casks, and installer receipts.
///
/// `OrphanCollector` used to compare an Application Support folder against app
/// names in `/Applications`, `~/Applications`, and `/System/Applications`
/// only. That misses Homebrew casks, Setapp apps, portable apps elsewhere in
/// the home folder, and apps identified by their bundle ID instead of a display
/// name. This index is read-only and loaded once per scan.
struct AppInventory: Sendable, Equatable {
    enum Source: String, Sendable, Equatable {
        case applications
        case userApplications
        case systemApplications
        case caskroom
        case spotlight
    }

    struct App: Sendable, Equatable {
        let name: String
        let bundleID: String?
        let path: String
        let source: Source

        init(name: String, bundleID: String? = nil, path: String, source: Source) {
            self.name = name
            self.bundleID = bundleID
            self.path = path
            self.source = source
        }
    }

    /// How an Application Support folder relates to the inventory.
    enum Ownership: Equatable, Sendable {
        /// An app bundle, cask token, or receipt matches this name.
        case owned
        /// Only a vendor identifier matches (for example `JetBrains` from
        /// `com.jetbrains.CLion`). The folder may be shared data.
        case vendor
        /// Nothing in the inventory matches.
        case none
    }

    let apps: [App]
    let receipts: [String]
    let caskTokens: [String]
    /// True when at least one standard app directory exists but could not be
    /// read. The collector downgrades every candidate to medium confidence in
    /// that case, because a matching app may be hiding behind permissions.
    let isIncomplete: Bool

    static let empty = AppInventory(
        apps: [],
        receipts: [],
        caskTokens: [],
        isIncomplete: true
    )

    // MARK: - Discovery

    static func load() async -> AppInventory {
        async let standard = scanStandardDirectories()
        async let casks = scanCaskrooms()
        async let receipts = readReceipts()
        async let spotlight = scanSpotlight()

        let standardResult = await standard
        let caskResult = await casks
        let receiptResult = await receipts
        let spotlightResult = await spotlight

        // Spotlight can return the same bundles as the standard scan. Dedupe
        // by path so the inventory stays small.
        var seen = Set<String>()
        let apps = (standardResult.apps + spotlightResult).filter { app in
            seen.insert(app.path).inserted
        }

        return AppInventory(
            apps: apps,
            receipts: receiptResult.packages,
            caskTokens: caskResult,
            isIncomplete: standardResult.failed || receiptResult.failed
        )
    }

    static func defaultAppDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "\(home)/Applications", "/System/Applications"]
    }

    static func defaultCaskrooms() -> [String] {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
    }

    /// Scans each registry directory and its immediate subdirectories, so
    /// `/Applications/Setapp/Foo.app` and `/Applications/Utilities/Bar.app`
    /// are included without descending into app bundles.
    static func scanStandardDirectories(
        directories: [String] = defaultAppDirectories(),
        fileManager: FileManager = .default
    ) -> (apps: [App], failed: Bool) {
        var apps: [App] = []
        var failed = false

        for directory in directories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
                failed = true
                continue
            }

            for entry in entries where !entry.hasPrefix(".") {
                let path = "\(directory)/\(entry)"

                if entry.hasSuffix(".app") {
                    apps.append(app(at: path, source: source(for: directory)))
                    continue
                }

                guard let children = try? fileManager.contentsOfDirectory(atPath: path) else {
                    continue
                }

                for child in children where child.hasSuffix(".app") {
                    apps.append(app(at: "\(path)/\(child)", source: source(for: directory)))
                }
            }
        }

        return (apps, failed)
    }

    private static func source(for directory: String) -> Source {
        if directory.hasPrefix("/System/") { return .systemApplications }
        if directory.hasPrefix("/Applications") { return .applications }
        return .userApplications
    }

    private static func app(at path: String, source: Source) -> App {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let displayName = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return App(
            name: displayName,
            bundleID: Bundle(path: path)?.bundleIdentifier,
            path: path,
            source: source
        )
    }

    static func scanCaskrooms(
        directories: [String] = defaultCaskrooms(),
        fileManager: FileManager = .default
    ) -> [String] {
        var tokens: [String] = []

        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
                continue
            }

            for entry in entries where !entry.hasPrefix(".") {
                tokens.append(entry)
            }
        }

        return tokens
    }

    static func readReceipts() async -> (packages: [String], failed: Bool) {
        do {
            let result = try await CommandRunner.run(
                "/usr/sbin/pkgutil",
                arguments: ["--pkgs"],
                timeout: 5
            )

            guard result.exitCode == 0 else { return ([], true) }

            let packages = result.stdout
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return (packages, false)
        } catch {
            return ([], true)
        }
    }

    /// Portable apps outside the standard folders. Only names are collected:
    /// reading every bundle ID from Spotlight results would cost more than the
    /// extra certainty is worth.
    static func scanSpotlight() async -> [App] {
        do {
            let result = try await CommandRunner.run(
                "/usr/bin/mdfind",
                arguments: ["kMDItemContentType == 'com.apple.application-bundle'"],
                timeout: 5
            )

            guard result.exitCode == 0 else { return [] }

            return result.stdout
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasSuffix(".app") && !isNoisePath($0) }
                .map { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    return App(
                        name: String(name.dropLast(4)),
                        bundleID: nil,
                        path: path,
                        source: .spotlight
                    )
                }
        } catch {
            return []
        }
    }

    /// Spotlight indexes app bundles inside build products, caches, and
    /// backups. Those are not installed apps and must not hide a real leftover.
    static func isNoisePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasPrefix("/system/")
            || lower.hasPrefix("/library/")
            || lower.hasPrefix("/private/")
            || lower.hasPrefix("/volumes/")
            || lower.contains("/caches/")
            || lower.contains("/deriveddata/")
            || lower.contains("/.trash/")
            || lower.contains("/backups.backupdb/")
    }

    // MARK: - Matching

    func ownership(for entry: String) -> Ownership {
        let needle = Self.normalize(entry)
        guard needle.count >= 3 else { return .owned }

        for app in apps {
            if Self.nameMatches(needle: needle, candidate: app.name) {
                return .owned
            }

            if let bundleID = app.bundleID, Self.bundleMatches(needle: needle, bundleID: bundleID) {
                return .owned
            }
        }

        for token in caskTokens {
            if Self.nameMatches(needle: needle, candidate: token) {
                return .owned
            }
        }

        for receipt in receipts {
            if Self.receiptMatches(needle: needle, receipt: receipt) {
                return .owned
            }
        }

        let vendors = Self.vendorTokens(apps: apps, receipts: receipts)
        if vendors.contains(needle) {
            return .vendor
        }

        return .none
    }

    /// The identifier that made a folder low confidence, for the row detail.
    func vendorIdentifier(for entry: String) -> String? {
        let needle = Self.normalize(entry)
        guard needle.count >= 3 else { return nil }

        let vendors = Self.vendorTokens(apps: apps, receipts: receipts)
        return vendors.contains(needle) ? needle : nil
    }

    static func nameMatches(needle: String, candidate: String) -> Bool {
        let haystack = normalize(candidate)
        guard haystack.count >= 3 else { return false }
        return haystack == needle || haystack.contains(needle) || needle.contains(haystack)
    }

    static func bundleMatches(needle: String, bundleID: String) -> Bool {
        let full = normalize(bundleID)
        guard full.count >= 3 else { return false }
        if full == needle { return true }

        guard let last = bundleID.split(separator: ".").last.map(String.init) else {
            return false
        }

        return nameMatches(needle: needle, candidate: last)
    }

    static func receiptMatches(needle: String, receipt: String) -> Bool {
        let full = normalize(receipt)
        guard full.count >= 3 else { return false }
        if full == needle { return true }

        guard let last = receipt.split(separator: ".").last.map(String.init) else {
            return false
        }

        return nameMatches(needle: needle, candidate: last)
    }

    /// Vendor component of `com.vendor.App` identifiers. Used only to downgrade
    /// shared vendor folders, never to claim an app is installed.
    static func vendorTokens(apps: [App], receipts: [String]) -> Set<String> {
        var tokens = Set<String>()

        for app in apps {
            guard let bundleID = app.bundleID else { continue }
            tokens.formUnion(vendorTokens(bundleID: bundleID))
        }

        for receipt in receipts {
            tokens.formUnion(vendorTokens(bundleID: receipt))
        }

        return tokens
    }

    static func vendorTokens(bundleID: String) -> Set<String> {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 3 else { return [] }

        let normalized = normalize(String(parts[1]))
        guard normalized.count >= 4, normalized != "apple" else { return [] }
        return [normalized]
    }

    static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
