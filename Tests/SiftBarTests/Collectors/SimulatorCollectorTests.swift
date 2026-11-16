import Foundation
import XCTest
@testable import SiftBar

final class SimulatorCollectorTests: XCTestCase {
    private let json = """
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
          {
            "name": "iPhone 16 Pro",
            "udid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "state": "Shutdown",
            "isAvailable": true,
            "dataPath": "/Users/test/Library/Developer/CoreSimulator/Devices/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/data",
            "dataPathSize": 2500000000
          },
          {
            "name": "iPhone 15",
            "udid": "11111111-2222-3333-4444-555555555555",
            "state": "Booted",
            "isAvailable": true,
            "dataPath": "/Users/test/Library/Developer/CoreSimulator/Devices/11111111-2222-3333-4444-555555555555/data",
            "dataPathSize": 600000000
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
          {
            "name": "iPad Pro",
            "udid": "99999999-8888-7777-6666-555555555555",
            "state": "Shutdown",
            "isAvailable": false,
            "dataPath": "/Users/test/Library/Developer/CoreSimulator/Devices/99999999-8888-7777-6666-555555555555/data",
            "dataPathSize": 1000000000
          },
          {
            "name": "Bad identifier",
            "udid": "not-a-uuid",
            "state": "Shutdown",
            "isAvailable": true,
            "dataPathSize": 900000000
          }
        ]
      }
    }
    """

    func testParsesDevicesAndSkipsInvalidIdentifiers() {
        let devices = SimulatorCollector.parse(Data(json.utf8))

        XCTAssertEqual(devices.count, 3)
        XCTAssertTrue(devices.allSatisfy { UUID(uuidString: $0.udid) != nil })
        XCTAssertEqual(devices.first { $0.name == "iPhone 16 Pro" }?.runtime, "iOS 18.2")
        XCTAssertEqual(devices.first { $0.name == "iPad Pro" }?.isAvailable, false)
    }

    func testRuntimeNameIsHumanReadable() {
        XCTAssertEqual(
            SimulatorCollector.runtimeName(from: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
            "iOS 18.2"
        )
        XCTAssertEqual(
            SimulatorCollector.runtimeName(from: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2"),
            "watchOS 11.2"
        )
        XCTAssertEqual(
            SimulatorCollector.runtimeName(from: "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4"),
            "iOS 27.2"
        )
    }

    func testBuildsSummaryUnavailableAndLargeDeviceRows() {
        let devices = SimulatorCollector.parse(Data(json.utf8))
        let items = SimulatorCollector.items(from: devices, simulatorRunning: true)

        XCTAssertEqual(items.first?.title, "iOS Simulator devices")
        XCTAssertEqual(items.first?.impactBytes, 4_100_000_000)
        XCTAssertTrue(items.first?.isInformational == true)

        let unavailable = items.first { $0.title == "Unavailable simulators" }
        XCTAssertEqual(unavailable?.impactBytes, 1_000_000_000)
        XCTAssertEqual(unavailable?.action, .deleteUnavailableSimulators(count: 1))
        XCTAssertTrue(unavailable?.canBeChanged == true)

        let large = items.first { $0.title == "iPhone 16 Pro simulator" }
        XCTAssertEqual(large?.impactBytes, 2_500_000_000)
        XCTAssertEqual(large?.risk, .caution)
        XCTAssertTrue(large?.canBeChanged == true)
        XCTAssertNotNil(large?.warning)

        // 600 MB is above the 500 MB cutoff and 100 MB-equivalent devices are
        // represented only by the summary.
        XCTAssertNotNil(items.first { $0.title == "iPhone 15 simulator" })
    }

    func testSmallDevicesStayInTheSummary() {
        let devices = [
            SimulatorCollector.Device(
                name: "Small",
                udid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                runtime: "iOS 18.2",
                state: "Shutdown",
                isAvailable: true,
                dataPath: "/tmp/small",
                bytes: 100_000_000
            )
        ]

        let items = SimulatorCollector.items(from: devices, simulatorRunning: false)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "iOS Simulator devices")
    }

    func testEmptyDeviceListProducesNoRows() {
        XCTAssertTrue(SimulatorCollector.items(from: [], simulatorRunning: false).isEmpty)
    }
}
