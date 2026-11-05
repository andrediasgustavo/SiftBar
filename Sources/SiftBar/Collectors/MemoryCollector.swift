import Foundation

struct MemoryCollector: Collector {
    let category: ItemCategory = .memory
    private let memory: MemoryStats

    init(memory: MemoryStats) {
        self.memory = memory
    }

    func collect() async -> [ScanItem] {
        var items: [ScanItem] = []

        if memory.swapUsedBytes > 0 {
            let risk: Risk = memory.swapUsedBytes > 2_000_000_000 ? .caution : .safe
            items.append(ScanItem(
                category: .memory,
                title: "Swap in use",
                detail: "Disk is being used as RAM. A reboot clears swap; quitting heavy apps prevents it from growing.",
                impactLabel: ByteCountFormatter.string(
                    fromByteCount: Int64(memory.swapUsedBytes),
                    countStyle: .memory
                ),
                impactBytes: Int64(memory.swapUsedBytes),
                risk: risk,
                action: .none,
                evidence: "sysctl -n vm.swapusage"
            ))
        }

        let pressureRisk: Risk
        let pressureDetail: String
        switch memory.pressure {
        case .normal:
            pressureRisk = .safe
            pressureDetail = "The system has enough free memory. No action needed."
        case .warning:
            pressureRisk = .caution
            pressureDetail = "Memory is getting tight. Consider closing unused apps."
        case .critical:
            pressureRisk = .dangerous
            pressureDetail = "The system is under memory pressure. Close heavy apps to avoid slowdowns."
        }

        items.append(ScanItem(
            category: .memory,
            title: "Memory pressure",
            detail: pressureDetail,
            impactLabel: memory.pressure.rawValue.capitalized,
            impactBytes: nil,
            risk: pressureRisk,
            action: .none,
            evidence: "memory_pressure"
        ))

        return items
    }
}
