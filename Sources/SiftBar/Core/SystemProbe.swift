import Foundation

enum SystemProbe {
    static func snapshotOrEmpty() async -> SystemSnapshot {
        (try? await snapshot()) ?? .empty
    }

    static func snapshot() async throws -> SystemSnapshot {
        async let memorySize = CommandRunner.run("/usr/sbin/sysctl", arguments: ["-n", "hw.memsize"])
        async let vmStat = CommandRunner.run("/usr/bin/vm_stat")
        async let swapUsage = CommandRunner.run("/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"])
        async let pressure = CommandRunner.run("/usr/bin/memory_pressure", timeout: 8)
        async let diskUsage = CommandRunner.run("/bin/df", arguments: ["-k", "/System/Volumes/Data"])
        async let topPhysMem = CommandRunner.run("/usr/bin/top", arguments: ["-l", "1", "-n", "0"], timeout: 10)
        async let apfsVolumes = CommandRunner.run("/usr/sbin/diskutil", arguments: ["apfs", "list", "-plist"], timeout: 10)

        var (memoryResult, vmResult, swapResult, pressureResult, diskResult) =
            try await (memorySize, vmStat, swapUsage, pressure, diskUsage)
        let topResult = try? await topPhysMem
        let volumeResult = try? await apfsVolumes

        // macOS exposes the read-only system volume at "/". The writable Data
        // volume holds the real usage numbers; fall back to "/" if unavailable.
        if diskResult.exitCode != 0 {
            diskResult = try await CommandRunner.run("/bin/df", arguments: ["-k", "/"])
        }

        let totalMemory = UInt64(memoryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let vm = parseVMStat(vmResult.stdout)
        let top = topResult.flatMap { $0.exitCode == 0 ? parseTopPhysMem($0.stdout) : nil }
        let usedMemory = min(top?.used ?? vm.usedBytes, totalMemory)
        let swapUsed = parseSwapUsed(swapResult.stdout) ?? 0
        let memoryPressure = parsePressure(pressureResult.stdout)

        let wiredBytes = top?.wired ?? vm.wiredBytes
        let compressedBytes = top?.compressed ?? vm.compressedBytes
        let freeMemory = min(top?.unused ?? vm.freeBytes, totalMemory)
        let appBytes = usedMemory > wiredBytes + compressedBytes
            ? usedMemory - wiredBytes - compressedBytes
            : vm.appBytes

        var disk = try parseDisk(diskResult.stdout)
        let volumes = volumeResult.flatMap {
            $0.exitCode == 0 ? parseAPFSVolumes(Data($0.stdout.utf8)) : nil
        } ?? []

        // `df` reports strict free blocks. macOS System Settings reports
        // "available for important usage", which also counts purgeable data.
        // Using that number reconciles SiftBar with the Finder and Settings.
        if let important = importantAvailableBytes(for: "/System/Volumes/Data") {
            let available = max(important, disk.freeBytes)
            disk = DiskStats(
                totalBytes: disk.totalBytes,
                usedBytes: max(0, disk.totalBytes - available),
                freeBytes: disk.freeBytes,
                dataVolumeUsedBytes: disk.dataVolumeUsedBytes,
                availableForImportantUsageBytes: available,
                purgeableBytes: max(0, available - disk.freeBytes),
                volumes: volumes
            )
        } else if !volumes.isEmpty {
            disk = DiskStats(
                totalBytes: disk.totalBytes,
                usedBytes: disk.usedBytes,
                freeBytes: disk.freeBytes,
                dataVolumeUsedBytes: disk.dataVolumeUsedBytes,
                volumes: volumes
            )
        }

        return SystemSnapshot(
            memory: MemoryStats(
                totalBytes: totalMemory,
                usedBytes: usedMemory,
                swapUsedBytes: swapUsed,
                pressure: memoryPressure,
                appBytes: min(appBytes, totalMemory),
                wiredBytes: min(wiredBytes, totalMemory),
                compressedBytes: min(compressedBytes, totalMemory),
                cachedBytes: min(vm.fileBackedBytes, totalMemory),
                freeBytes: freeMemory
            ),
            disk: disk
        )
    }

    static func importantAvailableBytes(for path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ), let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }

        return Int64(capacity)
    }

    struct TopPhysMem: Sendable, Equatable {
        let used: UInt64
        let wired: UInt64
        let compressed: UInt64
        let unused: UInt64
    }

    /// Parses the line `top` prints as:
    /// `PhysMem: 7545M used (1611M wired, 3432M compressor), 91M unused.`
    static func parseTopPhysMem(_ output: String) -> TopPhysMem? {
        let pattern = #"PhysMem:\s*([0-9.]+[KMG]?)\s+used\s+\(([0-9.]+[KMG]?)\s+wired,\s*([0-9.]+[KMG]?)\s+compressor\),\s*([0-9.]+[KMG]?)\s+unused"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ) else {
            return nil
        }

        func token(_ index: Int) -> UInt64? {
            guard let range = Range(match.range(at: index), in: output) else { return nil }
            return parseByteToken(String(output[range]))
        }

        guard let used = token(1),
              let wired = token(2),
              let compressed = token(3),
              let unused = token(4) else {
            return nil
        }

        return TopPhysMem(used: used, wired: wired, compressed: compressed, unused: unused)
    }

    /// Parses `diskutil apfs list -plist` and keeps the main container's
    /// volumes. Volume usage explains the part of "Used" that is not a folder:
    /// macOS, Preboot, Recovery, VM and the Data volume itself.
    static func parseAPFSVolumes(_ data: Data) -> [DiskVolume] {
        guard let object = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ), let root = object as? [String: Any],
              let containers = root["Containers"] as? [[String: Any]] else {
            return []
        }

        func capacity(_ container: [String: Any]) -> Int64 {
            (container["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
        }

        guard let main = containers.max(by: { capacity($0) < capacity($1) }),
              let rawVolumes = main["Volumes"] as? [[String: Any]] else {
            return []
        }

        return rawVolumes.compactMap { volume in
            guard let id = volume["DeviceIdentifier"] as? String,
                  let bytes = (volume["CapacityInUse"] as? NSNumber)?.int64Value,
                  bytes > 0 else {
                return nil
            }

            let roles = volume["Roles"] as? [String] ?? []
            let rawName = volume["Name"] as? String ?? id
            let name: String
            if roles.contains("System") {
                name = "macOS"
            } else if roles.contains("Data") {
                name = "Data"
            } else {
                name = rawName
            }

            return DiskVolume(id: id, name: name, roles: roles, bytes: bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    struct VMStat: Sendable, Equatable {
        let pageSize: UInt64
        let wiredBytes: UInt64
        let activeBytes: UInt64
        let compressedBytes: UInt64
        let freeBytes: UInt64
        let fileBackedBytes: UInt64
        let anonymousBytes: UInt64
        let purgeableBytes: UInt64

        var usedBytes: UInt64 {
            wiredBytes + activeBytes + compressedBytes
        }

        /// App memory as Activity Monitor's "App Memory" counter: anonymous
        /// pages that are not purgeable.
        var appBytes: UInt64 {
            anonymousBytes > purgeableBytes ? anonymousBytes - purgeableBytes : 0
        }
    }

    static func parseVMStat(_ output: String) -> VMStat {
        let lines = output.split(separator: "\n")

        var pageSize: UInt64 = 4096
        for line in lines where line.contains("page size of") {
            let digits = line.filter { $0.isNumber }
            if let value = UInt64(digits), value > 0 {
                pageSize = value
            }
            break
        }

        func pages(_ prefix: String) -> UInt64 {
            for line in lines where line.hasPrefix(prefix) {
                let digits = line.filter { $0.isNumber }
                return UInt64(digits) ?? 0
            }
            return 0
        }

        let wired = pages("Pages wired down:")
        let active = pages("Pages active:")
        let compressed = pages("Pages occupied by compressor:")
        let free = pages("Pages free:") + pages("Pages speculative:")
        let fileBacked = pages("File-backed pages:")
        let anonymous = pages("Anonymous pages:")
        let purgeable = pages("Pages purgeable:")

        return VMStat(
            pageSize: pageSize,
            wiredBytes: wired * pageSize,
            activeBytes: active * pageSize,
            compressedBytes: compressed * pageSize,
            freeBytes: free * pageSize,
            fileBackedBytes: fileBacked * pageSize,
            anonymousBytes: anonymous * pageSize,
            purgeableBytes: purgeable * pageSize
        )
    }

    static func parseSwapUsed(_ output: String) -> UInt64? {
        guard let range = output.range(of: "used = ") else { return nil }
        let remainder = output[range.upperBound...]
        guard let token = remainder.split(separator: " ").first else { return nil }
        return parseByteToken(String(token))
    }

    static func parseByteToken(_ token: String) -> UInt64? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let units: [(String, Double)] = [
            ("G", 1024 * 1024 * 1024),
            ("M", 1024 * 1024),
            ("K", 1024)
        ]

        for (suffix, multiplier) in units where trimmed.hasSuffix(suffix) {
            guard let value = Double(trimmed.dropLast()) else { return nil }
            return UInt64(value * multiplier)
        }

        return UInt64(trimmed)
    }

    static func parsePressure(_ output: String) -> MemoryPressure {
        for line in output.split(separator: "\n") where line.contains("System-wide memory free percentage") {
            let digits = line.filter { $0.isNumber }
            guard let percent = Int(digits) else { break }
            if percent < 10 { return .critical }
            if percent < 20 { return .warning }
            return .normal
        }
        return .normal
    }

    /// Parses the available space (bytes) from `df -k` output.
    static func parseFreeDisk(from output: String) throws -> Int64 {
        try parseDisk(output).freeBytes
    }

    static func parseDisk(_ output: String) throws -> DiskStats {
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { throw ProbeError.unexpectedOutput("df") }

        let fields = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 4,
              let blocks = Int64(fields[1]),
              let used = Int64(fields[2]),
              let available = Int64(fields[3]) else {
            throw ProbeError.unexpectedOutput("df")
        }

        let total = blocks * 1024
        let dataUsed = used * 1024
        let free = available * 1024

        // APFS makes `used + available` smaller than the container total
        // because snapshots, the system volume, and other volumes share the
        // same pool. System Settings therefore reports
        // `used = total - available`; use the same definition here.
        return DiskStats(
            totalBytes: total,
            usedBytes: max(0, total - free),
            freeBytes: free,
            dataVolumeUsedBytes: dataUsed
        )
    }
}

enum ProbeError: Error, LocalizedError {
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedOutput(let command):
            return "Could not parse the output of \(command)."
        }
    }
}
