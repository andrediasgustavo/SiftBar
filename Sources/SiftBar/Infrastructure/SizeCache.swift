import Foundation

/// Remembers measured path sizes between scans so the post-action refresh does
/// not walk the same trees again.
///
/// This is presentation data only: the cleanup whitelist and the final Trash
/// gate still decide what can be deleted. Entries expire after a short TTL and
/// are invalidated when a path is removed, so a recreated cache is measured
/// again instead of showing stale bytes.
final class SizeCache: @unchecked Sendable {
    struct Entry: Codable, Sendable {
        let bytes: Int64
        /// Modification date of the measured path when it was walked.
        let signature: Date
        let recordedAt: Date
    }

    static let shared = SizeCache()
    /// Used by tests and by callers that must always measure the real path.
    static let disabled = SizeCache(fileURL: nil)

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SiftBar/sizecache.json")
    }

    private let fileURL: URL?
    private let ttl: TimeInterval
    private let maxEntries: Int
    private let lock = NSLock()
    private var entries: [String: Entry]?

    init(
        fileURL: URL? = SizeCache.defaultURL,
        ttl: TimeInterval = 600,
        maxEntries: Int = 200
    ) {
        self.fileURL = fileURL
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    func lookup(path: String, signature: Date, now: Date = Date()) -> Int64? {
        guard isCacheable(path) else { return nil }

        lock.lock()
        defer { lock.unlock() }

        guard let entry = loadedEntries()[path] else { return nil }
        guard entry.signature == signature else { return nil }
        guard now.timeIntervalSince(entry.recordedAt) < ttl else { return nil }
        return entry.bytes
    }

    func store(path: String, bytes: Int64, signature: Date, now: Date = Date()) {
        guard isCacheable(path) else { return }

        lock.lock()
        defer { lock.unlock() }

        var values = loadedEntries()
        values[path] = Entry(bytes: bytes, signature: signature, recordedAt: now)

        if values.count > maxEntries {
            let oldest = values
                .sorted { $0.value.recordedAt < $1.value.recordedAt }
                .prefix(values.count - maxEntries)
            for (key, _) in oldest {
                values.removeValue(forKey: key)
            }
        }

        write(values)
    }

    /// Drops a path and everything measured below it.
    func invalidate(path: String) {
        guard fileURL != nil else { return }

        lock.lock()
        defer { lock.unlock() }

        let prefix = path + "/"
        var values = loadedEntries()
        values = values.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
        write(values)
    }

    func invalidateAll() {
        guard fileURL != nil else { return }

        lock.lock()
        defer { lock.unlock() }
        write([:])
    }

    // MARK: - Private

    /// Caching temporary paths is pointless: they change constantly. This also
    /// keeps the test suite from writing into the real user cache.
    private func isCacheable(_ path: String) -> Bool {
        guard fileURL != nil, !path.isEmpty else { return false }

        let temp = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .path
        let candidate = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .path

        return candidate != temp && !candidate.hasPrefix(temp + "/")
    }

    private func loadedEntries() -> [String: Entry] {
        if let entries { return entries }

        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            entries = [:]
            return [:]
        }

        entries = decoded
        return decoded
    }

    /// Best-effort persistence: a failed write never blocks a scan.
    private func write(_ values: [String: Entry]) {
        entries = values
        guard let fileURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(values)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Ignored on purpose.
        }
    }
}
