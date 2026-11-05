import Foundation

struct SystemSnapshot: Sendable {
    let totalMemoryBytes: UInt64
    let freeDiskBytes: Int64
}

enum SystemProbe {
    static func snapshot() async throws -> SystemSnapshot {
        async let memory = CommandRunner.run("/usr/sbin/sysctl", arguments: ["-n", "hw.memsize"])
        async let disk = CommandRunner.run("/bin/df", arguments: ["-k", "/"])

        let (memoryResult, diskResult) = try await (memory, disk)

        let rawMemory = memoryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalMemory = UInt64(rawMemory) ?? 0
        let freeDisk = try parseFreeDisk(from: diskResult.stdout)

        return SystemSnapshot(totalMemoryBytes: totalMemory, freeDiskBytes: freeDisk)
    }

    static func parseFreeDisk(from output: String) throws -> Int64 {
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else {
            throw ProbeError.unexpectedOutput("df")
        }

        let fields = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 4, let blocks = Int64(fields[3]) else {
            throw ProbeError.unexpectedOutput("df")
        }

        return blocks * 1024
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
