import XCTest
@testable import SiftBar

final class SystemProbeTests: XCTestCase {
    // MARK: - Disk

    func testParsesAvailableDiskSpaceFromDFOutput() throws {
        let output = """
        Filesystem      1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s1s1   971350180  12345678 123456789    10%   /
        """

        let bytes = try SystemProbe.parseFreeDisk(from: output)

        XCTAssertEqual(bytes, 123_456_789 * 1024)
    }

    func testParsesTotalUsedAndFreeDiskSpace() throws {
        let output = """
        Filesystem     1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s5    239362496 123217964  89429460    58%   /System/Volumes/Data
        """

        let disk = try SystemProbe.parseDisk(output)

        XCTAssertEqual(disk.totalBytes, 239_362_496 * 1024)
        XCTAssertEqual(disk.usedBytes, 123_217_964 * 1024)
        XCTAssertEqual(disk.freeBytes, 89_429_460 * 1024)
    }

    func testParsesSingleLineOutputWithoutHeaderAsError() {
        XCTAssertThrowsError(try SystemProbe.parseFreeDisk(from: "garbage"))
    }

    func testRejectsNonNumericAvailableBlocks() {
        let output = """
        Filesystem      1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s1s1   971350180  12345678    unknown    10%   /
        """

        XCTAssertThrowsError(try SystemProbe.parseFreeDisk(from: output))
    }

    // MARK: - vm_stat

    func testParsesVMStatPagesAndPageSize() {
        let output = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                               10000.
        Pages active:                             20000.
        Pages inactive:                           30000.
        Pages speculative:                         4000.
        Pages wired down:                          5000.
        Pages occupied by compressor:              1000.
        """

        let vm = SystemProbe.parseVMStat(output)

        XCTAssertEqual(vm.pageSize, 16_384)
        XCTAssertEqual(vm.wiredBytes, 5_000 * 16_384)
        XCTAssertEqual(vm.activeBytes, 20_000 * 16_384)
        XCTAssertEqual(vm.compressedBytes, 1_000 * 16_384)
        XCTAssertEqual(vm.freeBytes, 14_000 * 16_384)
        XCTAssertEqual(vm.usedBytes, 26_000 * 16_384)
    }

    func testVMStatFallsBackTo4096PageSizeWhenHeaderIsMissing() {
        let output = """
        Pages active:   100.
        Pages wired down: 50.
        """

        let vm = SystemProbe.parseVMStat(output)

        XCTAssertEqual(vm.pageSize, 4_096)
        XCTAssertEqual(vm.usedBytes, 150 * 4_096)
    }

    func testVMStatUnknownPagesAreZero() {
        let vm = SystemProbe.parseVMStat("Mach Virtual Memory Statistics: (page size of 4096 bytes)")

        XCTAssertEqual(vm.usedBytes, 0)
        XCTAssertEqual(vm.freeBytes, 0)
    }

    // MARK: - Swap units

    func testParsesSwapUsedInMegabytes() {
        let output = "vm.swapusage: total = 4096.00M  used = 1234.50M  free = 2861.50M  (encrypted)"

        let used = SystemProbe.parseSwapUsed(output)

        XCTAssertEqual(used, UInt64(1_234.5 * 1024 * 1024))
    }

    func testParsesSwapUsedInGigabytes() {
        let output = "vm.swapusage: total = 8.00G  used = 2.00G  free = 6.00G"

        XCTAssertEqual(SystemProbe.parseSwapUsed(output), 2 * 1024 * 1024 * 1024)
    }

    func testReturnsNilForMalformedSwapOutput() {
        XCTAssertNil(SystemProbe.parseSwapUsed("no swap information here"))
    }

    func testParsesByteTokensWithUnits() {
        XCTAssertEqual(SystemProbe.parseByteToken("512K"), 512 * 1024)
        XCTAssertEqual(SystemProbe.parseByteToken("2M"), 2 * 1024 * 1024)
        XCTAssertEqual(SystemProbe.parseByteToken("1.5G"), UInt64(1.5 * 1024 * 1024 * 1024))
        XCTAssertEqual(SystemProbe.parseByteToken("1024"), 1_024)
        XCTAssertEqual(SystemProbe.parseByteToken(" 64M\n"), 64 * 1024 * 1024)
    }

    func testRejectsInvalidByteTokens() {
        XCTAssertNil(SystemProbe.parseByteToken("abc"))
        XCTAssertNil(SystemProbe.parseByteToken("12X"))
        XCTAssertNil(SystemProbe.parseByteToken(""))
    }

    // MARK: - Memory pressure

    func testParsesNormalMemoryPressure() {
        let output = """
        The system has memory pressure status: normal.
        System-wide memory free percentage: 55%
        """

        XCTAssertEqual(SystemProbe.parsePressure(output), .normal)
    }

    func testParsesWarningMemoryPressureBoundaries() {
        XCTAssertEqual(
            SystemProbe.parsePressure("System-wide memory free percentage: 19%"),
            .warning
        )
        XCTAssertEqual(
            SystemProbe.parsePressure("System-wide memory free percentage: 10%"),
            .warning
        )
    }

    func testParsesCriticalMemoryPressureBelowTenPercent() {
        XCTAssertEqual(
            SystemProbe.parsePressure("System-wide memory free percentage: 9%"),
            .critical
        )
        XCTAssertEqual(
            SystemProbe.parsePressure("System-wide memory free percentage: 0%"),
            .critical
        )
    }

    func testDefaultsToNormalWhenPressureOutputIsMissing() {
        XCTAssertEqual(SystemProbe.parsePressure("unexpected output"), .normal)
        XCTAssertEqual(SystemProbe.parsePressure(""), .normal)
    }

    // MARK: - Live snapshot

    func testSnapshotReturnsRealSystemValues() async throws {
        let snapshot = try await SystemProbe.snapshot()

        XCTAssertGreaterThan(snapshot.totalMemoryBytes, 0)
        XCTAssertGreaterThan(snapshot.freeDiskBytes, 0)
        XCTAssertGreaterThan(snapshot.memory.totalBytes, 0)
        XCTAssertGreaterThan(snapshot.disk.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.memory.usedBytes, snapshot.memory.totalBytes)
    }

    func testSnapshotOrEmptyNeverThrows() async {
        let snapshot = await SystemProbe.snapshotOrEmpty()

        XCTAssertGreaterThan(snapshot.totalMemoryBytes, 0)
    }
}
