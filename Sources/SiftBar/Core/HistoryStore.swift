import Foundation

struct HistoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let itemID: UUID
    let title: String
    let category: String
    let command: String
    let success: Bool
    let message: String
    let reclaimedBytes: Int64

    init(item: ScanItem, report: ActionReport) {
        self.id = UUID()
        self.itemID = item.id
        self.title = item.title
        self.category = item.category.rawValue
        self.command = ActionExecutor.preview(for: item)
        self.success = report.success
        self.message = report.message
        self.reclaimedBytes = report.reclaimedBytes
    }
}

struct HistoryRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let entries: [HistoryEntry]

    var succeeded: Int {
        entries.filter(\.success).count
    }

    var failed: Int {
        entries.count - succeeded
    }

    var reclaimedBytes: Int64 {
        entries.filter(\.success).reduce(0) { $0 + $1.reclaimedBytes }
    }
}

/// Append-only audit log stored next to the app's data. History is best-effort:
/// a failed write never blocks or fails an action.
struct HistoryStore {
    let fileURL: URL

    private static let limit = 100

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SiftBar/history.json")
    }

    func load() -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryRecord].self, from: data)) ?? []
    }

    func append(_ record: HistoryRecord) {
        var records = load()
        records.append(record)

        if records.count > Self.limit {
            records.removeFirst(records.count - Self.limit)
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort: never break an action because history could not be written.
        }
    }
}
