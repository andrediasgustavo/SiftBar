import Foundation

/// Names the large app-data folders that the space map only counts in
/// aggregate. Everything here is read-only: Docker images, device backups and
/// virtual machines are user data, so SiftBar points to Finder or the app that
/// owns them instead of offering deletion.
struct LargeAppDataCollector: Collector {
    let category: ItemCategory = .disk

    static let minimumBytes: Int64 = 1_000_000_000
    static let limit = 8

    struct Candidate: Sendable, Equatable {
        let name: String
        let path: String
        let detail: String
    }

    struct Measured: Sendable, Equatable {
        let candidate: Candidate
        let bytes: Int64
    }

    func collect() async -> [ScanItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var measured: [Measured] = []

        for candidate in Self.candidates(home: home) {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            guard let bytes = await PathSizer.sizeInBytes(of: candidate.path, timeout: 20),
                  bytes >= Self.minimumBytes else { continue }
            measured.append(Measured(candidate: candidate, bytes: bytes))
        }

        let cloudChildren = await PathSizer.childDirectorySizes(
            of: "\(home)/Library/CloudStorage",
            timeout: 20
        )
        for child in cloudChildren where child.bytes >= Self.minimumBytes {
            let name = URL(fileURLWithPath: child.path).lastPathComponent
            measured.append(Measured(
                candidate: Candidate(
                    name: "\(name) cloud files",
                    path: child.path,
                    detail: "Files synced by \(name). This is your data, not a cache."
                ),
                bytes: child.bytes
            ))
        }

        return Self.items(from: measured)
    }

    static func candidates(home: String) -> [Candidate] {
        [
            Candidate(
                name: "Docker disk image",
                path: "\(home)/Library/Containers/com.docker.docker/Data/vms",
                detail: "Containers, images and volumes. Open Docker Desktop to reclaim space safely."
            ),
            Candidate(
                name: "OrbStack disk image",
                path: "\(home)/Library/Containers/com.orbstack.OrbStack/Data",
                detail: "Containers and virtual machines managed by OrbStack."
            ),
            Candidate(
                name: "UTM virtual machines",
                path: "\(home)/Library/Containers/com.utmapp.UTM/Data",
                detail: "Virtual machine data. Open UTM to review and remove them."
            ),
            Candidate(
                name: "Parallels virtual machines",
                path: "\(home)/Library/Containers/com.parallels.desktop.console/Data",
                detail: "Virtual machine data. Open Parallels to review and remove them."
            ),
            Candidate(
                name: "VMware virtual machines",
                path: "\(home)/Library/Containers/com.vmware.fusion/Data",
                detail: "Virtual machine data. Open VMware Fusion to review and remove them."
            ),
            Candidate(
                name: "iPhone backups",
                path: "\(home)/Library/Application Support/MobileSync/Backup",
                detail: "Device backups. Review them in Finder; deleting a backup cannot be undone."
            ),
            Candidate(
                name: "Xcode build archives",
                path: "\(home)/Library/Developer/Xcode/Archives",
                detail: "Archived builds. Review them in Finder; SiftBar will not remove them."
            ),
            Candidate(
                name: "Steam games",
                path: "\(home)/Library/Application Support/Steam/steamapps",
                detail: "Installed games and their data. Manage them in Steam."
            )
        ]
    }

    static func items(from measured: [Measured], limit: Int = LargeAppDataCollector.limit) -> [ScanItem] {
        measured
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { entry in
                ScanItem(
                    category: .disk,
                    title: entry.candidate.name,
                    detail: "\(format(entry.bytes)) of app data, not a cache. \(entry.candidate.detail)",
                    impactLabel: format(entry.bytes),
                    impactBytes: entry.bytes,
                    risk: .caution,
                    action: .none,
                    evidence: entry.candidate.path,
                    isInformational: true,
                    isSlowRefresh: true,
                    revealPath: entry.candidate.path
                )
            }
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
