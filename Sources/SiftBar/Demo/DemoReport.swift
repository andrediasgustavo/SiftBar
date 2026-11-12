import Foundation

/// Synthetic report used only for README screenshots (`--demo`). Keeping the
/// sample data here means screenshots never expose a real user's paths or apps.
enum DemoReport {
    static func make() -> ScanReport {
        let disk = DiskStats(
            totalBytes: 245_110_000_000,
            usedBytes: 142_590_000_000,
            freeBytes: 99_700_000_000,
            dataVolumeUsedBytes: 114_300_000_000,
            availableForImportantUsageBytes: 102_520_000_000,
            purgeableBytes: 2_820_000_000,
            volumes: [
                DiskVolume(id: "disk3s5", name: "Data", roles: ["Data"], bytes: 114_300_000_000),
                DiskVolume(id: "disk3s1", name: "macOS", roles: ["System"], bytes: 13_760_000_000),
                DiskVolume(id: "disk3s2", name: "Preboot", roles: ["Preboot"], bytes: 9_710_000_000),
                DiskVolume(id: "disk3s6", name: "VM", roles: ["VM"], bytes: 3_220_000_000),
                DiskVolume(id: "disk3s3", name: "Recovery", roles: ["Recovery"], bytes: 1_520_000_000),
                DiskVolume(id: "disk3s4", name: "Update", roles: ["Update"], bytes: 79_800_000)
            ]
        )

        let memory = MemoryStats(
            totalBytes: 16_000_000_000,
            usedBytes: 9_130_000_000,
            swapUsedBytes: 0,
            pressure: .normal,
            appBytes: 5_200_000_000,
            wiredBytes: 2_100_000_000,
            compressedBytes: 1_830_000_000,
            cachedBytes: 5_900_000_000,
            freeBytes: 970_000_000
        )

        var items: [ScanItem] = []

        // Startup
        items.append(ScanItem(
            category: .startup,
            title: "Failing launch item: com.example.legacy",
            detail: "launchctl reports last exit status 1. Review whether this agent is still needed.",
            impactLabel: "exit 1",
            impactBytes: nil,
            risk: .caution,
            action: .disableLaunchItem(label: "com.example.legacy"),
            evidence: "launchctl list"
        ))
        items.append(ScanItem(
            category: .startup,
            title: "Launch item: com.example.user-agent",
            detail: "Registered in /Users/example/Library/LaunchAgents as a launch agent. Disable it only if the related app or service is no longer needed.",
            impactLabel: "launch agent",
            impactBytes: nil,
            risk: .safe,
            action: .disableLaunchItem(label: "com.example.user-agent"),
            evidence: "/Users/example/Library/LaunchAgents"
        ))
        items.append(ScanItem(
            category: .startup,
            title: "Launch item: com.example.system-daemon",
            detail: "Registered in /Library/LaunchDaemons as a launch daemon. Disable it only if the related app or service is no longer needed.",
            impactLabel: "launch daemon",
            impactBytes: nil,
            risk: .caution,
            action: .disableLaunchItem(label: "com.example.system-daemon"),
            evidence: "/Library/LaunchDaemons"
        ))
        items.append(ScanItem(
            category: .startup,
            title: "Disabled launch item: com.example.helper",
            detail: "Disabled with launchctl. Enable it to load it again at login. Registered in /Users/example/Library/LaunchAgents as a launch agent.",
            impactLabel: "disabled",
            impactBytes: nil,
            risk: .safe,
            action: .enableLaunchItem(label: "com.example.helper"),
            evidence: "/Users/example/Library/LaunchAgents"
        ))

        // Processes
        items.append(ScanItem(
            category: .processes,
            title: "184 processes running",
            detail: "Apps whose processes total at least 150 MB are listed below. Helpers are grouped under the app, sorted by total resident memory.",
            impactLabel: "184 processes",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: "ps -Ao pid,user,rss,comm",
            isInformational: true
        ))
        items.append(ScanItem(
            category: .processes,
            title: "Design Helper",
            detail: "2 processes · example · 1.4 GB resident. SiftBar quits the main process; helpers usually exit with it. Expand to quit an individual process.",
            impactLabel: "1.4 GB",
            impactBytes: 1_400_000_000,
            risk: .caution,
            action: .killProcess(pid: 5151, name: "Design Helper"),
            evidence: "ps -Ao pid,user,rss,comm",
            children: [
                ScanItem(
                    category: .processes,
                    title: "Design Helper · PID 5151",
                    detail: "PID 5151 · example · 900 MB resident.",
                    impactLabel: "900 MB",
                    impactBytes: 900_000_000,
                    risk: .safe,
                    action: .killProcess(pid: 5151, name: "Design Helper"),
                    evidence: "ps -Ao pid,user,rss,comm"
                ),
                ScanItem(
                    category: .processes,
                    title: "Design Helper · PID 5152",
                    detail: "PID 5152 · example · 500 MB resident.",
                    impactLabel: "500 MB",
                    impactBytes: 500_000_000,
                    risk: .safe,
                    action: .killProcess(pid: 5152, name: "Design Helper Helper"),
                    evidence: "ps -Ao pid,user,rss,comm"
                )
            ]
        ))
        items.append(ScanItem(
            category: .processes,
            title: "Example Browser",
            detail: "PID 4242 · example · 612 MB resident.",
            impactLabel: "612 MB",
            impactBytes: 612_000_000,
            risk: .safe,
            action: .killProcess(pid: 4242, name: "Example Browser"),
            evidence: "ps -Ao pid,user,rss,comm"
        ))

        // Services
        items.append(ScanItem(
            category: .services,
            title: "Homebrew service: postgresql",
            detail: "Runs automatically at login. Stop it if you do not need it every session. User: example.",
            impactLabel: "started",
            impactBytes: nil,
            risk: .safe,
            action: .stopService(name: "postgresql"),
            evidence: "brew services list"
        ))

        // Caches
        items.append(ScanItem(
            category: .caches,
            title: "Xcode DerivedData",
            detail: "Recreatable cache data. Deleting it may slow the next run of the related tool, but does not remove personal files.",
            impactLabel: "2.1 GB",
            impactBytes: 2_100_000_000,
            risk: .safe,
            action: .deletePath(path: "/Users/example/Library/Developer/Xcode/DerivedData", bytes: 2_100_000_000),
            evidence: "du -sk /Users/example/Library/Developer/Xcode/DerivedData",
            warning: "Xcode is running. Quit it before moving this cache to the Trash."
        ))
        items.append(ScanItem(
            category: .caches,
            title: "npm cache",
            detail: "Recreatable cache data. Deleting it may slow the next run of the related tool, but does not remove personal files.",
            impactLabel: "820 MB",
            impactBytes: 820_000_000,
            risk: .safe,
            action: .deletePath(path: "/Users/example/.npm/_cacache", bytes: 820_000_000),
            evidence: "du -sk /Users/example/.npm/_cacache"
        ))
        items.append(ScanItem(
            category: .caches,
            title: "Design Helper cache",
            detail: "Recreatable cache data. Deleting it may slow the next run of the related tool, but does not remove personal files.",
            impactLabel: "1.1 GB",
            impactBytes: 1_100_000_000,
            risk: .caution,
            action: .deletePath(path: "/Users/example/Library/Caches/com.example.designhelper", bytes: 1_100_000_000),
            evidence: "du -sk /Users/example/Library/Caches/com.example.designhelper",
            warning: "Design Helper is running. Quit it before moving this cache to the Trash."
        ))

        // Leftovers
        let leftovers: [(String, Int64)] = [
            ("OldApp", 320_000_000),
            ("LegacyTool", 480_000_000)
        ]
        for (name, bytes) in leftovers {
            items.append(ScanItem(
                category: .leftovers,
                title: "Possible leftover: \(name)",
                detail: "No app named \(name) is installed in /Applications, ~/Applications or /System/Applications. This folder can contain settings, history, saved games, or licenses, so it is not the same as a cache. Open it in Finder before deleting.",
                impactLabel: format(bytes),
                impactBytes: bytes,
                risk: .caution,
                action: .trashLeftover(path: "/Users/example/Library/Application Support/\(name)", bytes: bytes),
                evidence: "/Users/example/Library/Application Support/\(name)",
                warning: "Review the contents first. This is app data, not recreatable cache."
            ))
        }

        // Memory
        items.append(ScanItem(
            category: .memory,
            title: "Memory pressure",
            detail: "The system has enough free memory. No action needed.",
            impactLabel: "Normal",
            impactBytes: nil,
            risk: .safe,
            action: .none,
            evidence: "memory_pressure",
            isInformational: true
        ))

        // Disk summary and space map
        items.append(ScanItem(
            category: .disk,
            title: "Startup disk",
            detail: "142.59 GB used of 245.11 GB. 102.52 GB available, matching System Settings. macOS can also reclaim 2.82 GB of purgeable space on demand.",
            impactLabel: "102.52 GB available",
            impactBytes: 102_520_000_000,
            risk: .safe,
            action: .none,
            evidence: "df -k /System/Volumes/Data + volumeAvailableCapacityForImportantUsage",
            isInformational: true
        ))

        let breakdown: [(String, Int64, String)] = [
            ("System & other", 45_070_000_000, "Not measured by SiftBar: Pictures/Photos, macOS itself, /System, /private, snapshots, purgeable space and other volumes. SiftBar will not delete any of it."),
            ("App data", 27_200_000_000, "Application Support, Containers and Group Containers. This is app data, not cache."),
            ("Developer", 18_500_000_000, "Xcode, Android SDK/emulator, Gradle and npm data."),
            ("Applications", 9_500_000_000, "App bundles in /Applications and ~/Applications."),
            ("System-wide data", 5_400_000_000, "Support files and caches installed in /Library."),
            ("Caches", 4_100_000_000, "Recreatable caches. The Caches tab lists what SiftBar can move to the Trash."),
            ("Documents & media", 3_200_000_000, "Desktop, Documents and Downloads."),
            ("iCloud Drive", 128_000_000, "Files stored in iCloud Drive and downloaded to this Mac.")
        ]
        for (name, bytes, detail) in breakdown {
            items.append(ScanItem(
                category: .disk,
                title: name,
                detail: "\(format(bytes)). \(detail)",
                impactLabel: format(bytes),
                impactBytes: bytes,
                risk: .safe,
                action: .none,
                evidence: "du -sk /Users/example",
                isInformational: true,
                isBreakdown: true
            ))
        }

        items.append(ScanItem(
            category: .disk,
            title: "Large folder: Design Assets",
            detail: "2.4 GB in ~/Documents/Design Assets. Review in Finder before deleting anything; SiftBar will not remove it for you.",
            impactLabel: "2.4 GB",
            impactBytes: 2_400_000_000,
            risk: .caution,
            action: .none,
            evidence: "/Users/example/Documents/Design Assets"
        ))

        return ScanReport(
            generatedAt: Date(),
            items: ScanCoordinator.sort(items),
            memory: memory,
            disk: disk
        )
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
