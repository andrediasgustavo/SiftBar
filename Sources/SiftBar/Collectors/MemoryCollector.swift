import Foundation

struct MemoryCollector: Collector {
    let category: ItemCategory = .memory
    private let memory: MemoryStats

    init(memory: MemoryStats) {
        self.memory = memory
    }

    func collect() async -> [ScanItem] {
        Self.items(for: memory)
    }

    static func items(for memory: MemoryStats) -> [ScanItem] {
        var items: [ScanItem] = []

        if memory.swapUsedBytes > 0 {
            items.append(ScanItem(
                category: .memory,
                title: "Swap in use",
                detail: "Disk is being used as RAM. A reboot clears swap; quitting heavy apps prevents it from growing.",
                impactLabel: ByteCountFormatter.string(
                    fromByteCount: Int64(memory.swapUsedBytes),
                    countStyle: .memory
                ),
                impactBytes: Int64(memory.swapUsedBytes),
                risk: swapRisk(for: memory.swapUsedBytes),
                action: .none,
                evidence: "sysctl -n vm.swapusage"
            ))
        }

        items.append(ScanItem(
            category: .memory,
            title: "Memory pressure",
            detail: pressureDetail(for: memory.pressure),
            impactLabel: memory.pressure.rawValue.capitalized,
            impactBytes: nil,
            risk: pressureRisk(for: memory.pressure),
            action: .none,
            evidence: "memory_pressure"
        ))

        return items
    }

    /// More than 2 GB of swap means the machine is short on physical memory.
    static func swapRisk(for bytes: UInt64) -> Risk {
        bytes > 2_000_000_000 ? .caution : .safe
    }

    static func pressureRisk(for pressure: MemoryPressure) -> Risk {
        switch pressure {
        case .normal: return .safe
        case .warning: return .caution
        case .critical: return .dangerous
        }
    }

    static func pressureDetail(for pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal:
            return "The system has enough free memory. No action needed."
        case .warning:
            return "Memory is getting tight. Consider closing unused apps."
        case .critical:
            return "The system is under memory pressure. Close heavy apps to avoid slowdowns."
        }
    }
}
