import XCTest
@testable import SiftBar

final class MemoryCollectorTests: XCTestCase {
    private func stats(
        total: UInt64 = 8_589_934_592,
        used: UInt64 = 4_000_000_000,
        swap: UInt64 = 0,
        pressure: MemoryPressure = .normal
    ) -> MemoryStats {
        MemoryStats(totalBytes: total, usedBytes: used, swapUsedBytes: swap, pressure: pressure)
    }

    func testWithoutSwapOnlyReportsPressure() {
        let items = MemoryCollector.items(for: stats())

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Memory pressure")
        XCTAssertEqual(items[0].risk, .safe)
        XCTAssertEqual(items[0].impactLabel, "Normal")
        XCTAssertNil(items[0].impactBytes)
        XCTAssertEqual(items[0].action, .none)
        XCTAssertEqual(items[0].evidence, "memory_pressure")
    }

    func testWithSwapReportsSwapFirst() {
        let items = MemoryCollector.items(for: stats(swap: 1_500_000_000))

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Swap in use")
        XCTAssertEqual(items[0].impactBytes, 1_500_000_000)
        XCTAssertEqual(items[0].action, .none)
        XCTAssertEqual(items[0].evidence, "sysctl -n vm.swapusage")
        XCTAssertEqual(items[1].title, "Memory pressure")
    }

    func testSwapRiskThreshold() {
        XCTAssertEqual(MemoryCollector.swapRisk(for: 0), .safe)
        XCTAssertEqual(MemoryCollector.swapRisk(for: 2_000_000_000), .safe)
        XCTAssertEqual(MemoryCollector.swapRisk(for: 2_000_000_001), .caution)
    }

    func testPressureRiskMapping() {
        XCTAssertEqual(MemoryCollector.pressureRisk(for: .normal), .safe)
        XCTAssertEqual(MemoryCollector.pressureRisk(for: .warning), .caution)
        XCTAssertEqual(MemoryCollector.pressureRisk(for: .critical), .dangerous)
    }

    func testWarningPressureProducesCautionItem() {
        let items = MemoryCollector.items(for: stats(pressure: .warning))

        XCTAssertEqual(items[0].risk, .caution)
        XCTAssertEqual(items[0].impactLabel, "Warning")
        XCTAssertTrue(items[0].detail.contains("closing unused apps"))
    }

    func testCriticalPressureProducesDangerousItem() {
        let items = MemoryCollector.items(for: stats(pressure: .critical))

        XCTAssertEqual(items[0].risk, .dangerous)
        XCTAssertEqual(items[0].impactLabel, "Critical")
        XCTAssertTrue(items[0].detail.contains("memory pressure"))
    }

    func testCollectMatchesStaticItems() async {
        let memory = stats(swap: 3_000_000_000, pressure: .warning)
        let collector = MemoryCollector(memory: memory)

        let collected = await collector.collect()
        let expected = MemoryCollector.items(for: memory)

        XCTAssertEqual(collected.count, expected.count)
        XCTAssertEqual(collected.map(\.title), expected.map(\.title))
        XCTAssertEqual(collected.map(\.risk), expected.map(\.risk))
    }
}
