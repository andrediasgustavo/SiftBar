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

        var (memoryResult, vmResult, swapResult, pressureResult, diskResult) =
            try await (memorySize, vmStat, swapUsage, pressure, diskUsage)

        // macOS exposes the read-only system volume at "/". The writable Data
        // volume holds the real usage numbers; fall back to "/" if unavailable.
        if diskResult.exitCode != 0 {
            diskResult = try await CommandRunner.run("/bin/df", arguments: ["-k", "/"])
        }

        let totalMemory = UInt64(memoryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let vm = parseVMStat(vmResult.stdout)
        let usedMemory = min(vm.wired + vm.active + vm.compressed, totalMemory)
        let swapUsed = parseSwapUsed(swapResult.stdout) ?? 0
        let memoryPressure = parsePressure(pressureResult.stdout)
        let disk = try parseDisk(diskResult.stdout)

        return SystemSnapshot(
            memory: MemoryStats(
                totalBytes: totalMemory,
                usedBytes: usedMemory,
                swapUsedBytes: swapUsed,
                pressure: memoryPressure
            ),
            disk: disk
        )
    }

    private struct VMStat {
        let wired: UInt64
        let active: UInt64
        let compressed: UInt64
        let free: UInt64
    }

    private static func parseVMStat(_ output: String) -> VMStat {
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

        return VMStat(
            wired: wired * pageSize,
            active: active * pageSize,
            compressed: compressed * pageSize,
            free: free * pageSize
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

    private static func parsePressure(_ output: String) -> MemoryPressure {
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

    private static func parseDisk(_ output: String) throws -> DiskStats {
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { throw ProbeError.unexpectedOutput("df") }

        let fields = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 4,
              let blocks = Int64(fields[1]),
              let used = Int64(fields[2]),
              let available = Int64(fields[3]) else {
            throw ProbeError.unexpectedOutput("df")
        }

        return DiskStats(
            totalBytes: blocks * 1024,
            usedBytes: used * 1024,
            freeBytes: available * 1024
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
