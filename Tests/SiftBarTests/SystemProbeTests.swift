import Foundation
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
        XCTAssertEqual(disk.usedBytes, (239_362_496 - 89_429_460) * 1024)
        XCTAssertEqual(disk.freeBytes, 89_429_460 * 1024)
        XCTAssertEqual(disk.dataVolumeUsedBytes, 123_217_964 * 1024)
        XCTAssertEqual(disk.importantFreeBytes, disk.freeBytes)
    }

    func testParsedDiskUsesContainerUsageRatherThanTheDataVolume() throws {
        let output = """
        Filesystem     1024-blocks      Used Available Capacity  Mounted on
        /dev/disk3s5    239362496 162349720  50297000    77%   /System/Volumes/Data
        """

        let disk = try SystemProbe.parseDisk(output)

        XCTAssertEqual(disk.dataVolumeUsedBytes, 162_349_720 * 1024)
        XCTAssertEqual(disk.usedBytes, (239_362_496 - 50_297_000) * 1024)
        XCTAssertNotEqual(disk.usedBytes, disk.dataVolumeUsedBytes)
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
        XCTAssertEqual(vm.appBytes, 0)
    }

    func testVMStatParsesFileBackedAnonymousAndPurgeablePages() {
        let output = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages purgeable:                             100.
        File-backed pages:                          2000.
        Anonymous pages:                            3000.
        """

        let vm = SystemProbe.parseVMStat(output)

        XCTAssertEqual(vm.fileBackedBytes, 2_000 * 16_384)
        XCTAssertEqual(vm.anonymousBytes, 3_000 * 16_384)
        XCTAssertEqual(vm.purgeableBytes, 100 * 16_384)
        XCTAssertEqual(vm.appBytes, 2_900 * 16_384)
    }

    // MARK: - top PhysMem

    func testParsesTopPhysMemLikeActivityMonitor() throws {
        let output = """
        Processes: 673 total, 4 running
        PhysMem: 7545M used (1611M wired, 3432M compressor), 91M unused.
        VM: 361T vsize
        """

        let memory = try XCTUnwrap(SystemProbe.parseTopPhysMem(output))

        XCTAssertEqual(memory.used, 7_545 * 1024 * 1024)
        XCTAssertEqual(memory.wired, 1_611 * 1024 * 1024)
        XCTAssertEqual(memory.compressed, 3_432 * 1024 * 1024)
        XCTAssertEqual(memory.unused, 91 * 1024 * 1024)
    }

    func testParsesTopPhysMemWithGigabyteTokens() throws {
        let output = "PhysMem: 1.5G used (512M wired, 1G compressor), 2G unused."

        let memory = try XCTUnwrap(SystemProbe.parseTopPhysMem(output))

        XCTAssertEqual(memory.used, UInt64(1.5 * 1024 * 1024 * 1024))
        XCTAssertEqual(memory.unused, 2 * 1024 * 1024 * 1024)
    }

    func testRejectsMalformedTopPhysMem() {
        XCTAssertNil(SystemProbe.parseTopPhysMem("PhysMem: not enough data"))
    }

    // MARK: - APFS volumes

    func testParsesVolumesFromTheMainAPFSContainer() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Containers</key>
            <array>
                <dict>
                    <key>CapacityCeiling</key>
                    <integer>100</integer>
                    <key>Volumes</key>
                    <array>
                        <dict>
                            <key>DeviceIdentifier</key><string>disk9s1</string>
                            <key>Name</key><string>Small</string>
                            <key>Roles</key><array><string>Data</string></array>
                            <key>CapacityInUse</key><integer>50</integer>
                        </dict>
                    </array>
                </dict>
                <dict>
                    <key>CapacityCeiling</key>
                    <integer>1000</integer>
                    <key>Volumes</key>
                    <array>
                        <dict>
                            <key>DeviceIdentifier</key><string>disk3s1</string>
                            <key>Name</key><string>Macintosh HD</string>
                            <key>Roles</key><array><string>System</string></array>
                            <key>CapacityInUse</key><integer>500</integer>
                        </dict>
                        <dict>
                            <key>DeviceIdentifier</key><string>disk3s5</string>
                            <key>Name</key><string>Data</string>
                            <key>Roles</key><array><string>Data</string></array>
                            <key>CapacityInUse</key><integer>400</integer>
                        </dict>
                        <dict>
                            <key>DeviceIdentifier</key><string>disk3s6</string>
                            <key>Name</key><string>VM</string>
                            <key>Roles</key><array><string>VM</string></array>
                            <key>CapacityInUse</key><integer>0</integer>
                        </dict>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let volumes = SystemProbe.parseAPFSVolumes(Data(xml.utf8))

        XCTAssertEqual(volumes.map(\.name), ["macOS", "Data"])
        XCTAssertEqual(volumes.map(\.bytes), [500, 400])
        XCTAssertEqual(volumes[0].id, "disk3s1")
        XCTAssertTrue(volumes[0].isSystem)
    }

    func testMalformedAPFSPlistsReturnNoVolumes() {
        XCTAssertTrue(SystemProbe.parseAPFSVolumes(Data("not a plist".utf8)).isEmpty)
        XCTAssertTrue(SystemProbe.parseAPFSVolumes(Data()).isEmpty)
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

    func testSnapshotIncludesAPFSVolumeUsage() async throws {
        let snapshot = try await SystemProbe.snapshot()

        XCTAssertFalse(snapshot.disk.volumes.isEmpty)
        XCTAssertTrue(snapshot.disk.volumes.contains { $0.roles.contains("Data") })
    }
}
