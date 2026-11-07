import XCTest
@testable import SiftBar

final class CacheCollectorTests: XCTestCase {
    func testTargetsCoverKnownCaches() {
        let targets = CacheCollector.targets(home: "/Users/tester")

        XCTAssertEqual(targets.count, 8)
        XCTAssertEqual(targets.first?.name, "npm")
        XCTAssertEqual(targets.first?.path, "/Users/tester/.npm/_cacache")
        XCTAssertEqual(targets.first?.risk, .safe)
        XCTAssertTrue(targets.contains { $0.name == "Homebrew" && $0.risk == .safe })
        XCTAssertTrue(targets.contains { $0.name == "General" && $0.risk == .caution })
        XCTAssertTrue(targets.contains { $0.path == "/Library/Developer/CoreSimulator/Caches" })
    }

    func testTargetsUseTheProvidedHomeDirectory() {
        let targets = CacheCollector.targets(home: "/tmp/home")

        XCTAssertTrue(targets.allSatisfy { $0.path.hasPrefix("/tmp/home") || $0.path.hasPrefix("/Library") })
    }

    func testRelatedAppsAreSetForCachesThatAppsUse() {
        let targets = CacheCollector.targets(home: "/Users/tester")

        XCTAssertEqual(targets.first { $0.name == "Xcode DerivedData" }?.relatedApps, ["xcode"])
        XCTAssertEqual(targets.first { $0.name == "CoreSimulator (user)" }?.relatedApps, ["simulator", "coresimulatorbridge"])
        XCTAssertEqual(targets.first { $0.name == "npm" }?.relatedApps, [])
    }

    func testRunningRelatedAppAddsAWarning() {
        let target = CacheCollector.Target(
            name: "Xcode DerivedData",
            path: "/tmp/DerivedData",
            risk: .safe,
            relatedApps: ["xcode"]
        )
        let items = CacheCollector.items(
            from: [CacheCollector.Measured(target: target, bytes: 42)],
            running: ["xcode"]
        )

        XCTAssertEqual(
            items[0].warning,
            "Xcode is running. Quit it before moving this cache to the Trash."
        )
    }

    func testUnrelatedRunningAppDoesNotWarn() {
        let target = CacheCollector.Target(
            name: "Xcode DerivedData",
            path: "/tmp/DerivedData",
            risk: .safe,
            relatedApps: ["xcode"]
        )
        let items = CacheCollector.items(
            from: [CacheCollector.Measured(target: target, bytes: 42)],
            running: ["safari"]
        )

        XCTAssertNil(items[0].warning)
    }

    func testWarningListsEveryRunningRelatedApp() {
        let target = CacheCollector.Target(
            name: "CoreSimulator (user)",
            path: "/tmp/CoreSimulator",
            risk: .safe,
            relatedApps: ["simulator", "coresimulatorbridge"]
        )
        let items = CacheCollector.items(
            from: [CacheCollector.Measured(target: target, bytes: 42)],
            running: ["simulator", "coresimulatorbridge"]
        )

        XCTAssertEqual(
            items[0].warning,
            "Simulator and CoreSimulatorBridge are running. Quit them before moving this cache to the Trash."
        )
    }

    func testItemsAreSortedBySize() {
        let measured = [
            CacheCollector.Measured(
                target: .init(name: "npm", path: "/tmp/npm", risk: .safe),
                bytes: 10 * 1024 * 1024
            ),
            CacheCollector.Measured(
                target: .init(name: "Homebrew", path: "/tmp/brew", risk: .safe),
                bytes: 500 * 1024 * 1024
            )
        ]

        let items = CacheCollector.items(from: measured)

        XCTAssertEqual(items.map(\.title), ["Homebrew cache", "npm cache"])
        XCTAssertEqual(items[0].impactBytes, 500 * 1024 * 1024)
        XCTAssertEqual(items[1].impactBytes, 10 * 1024 * 1024)
    }

    func testItemsUseDeletePathActionAndEvidence() {
        let target = CacheCollector.Target(name: "Xcode DerivedData", path: "/tmp/DerivedData", risk: .safe)
        let items = CacheCollector.items(from: [
            CacheCollector.Measured(target: target, bytes: 42)
        ])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].category, .caches)
        XCTAssertEqual(items[0].risk, .safe)
        XCTAssertEqual(items[0].action, .deletePath(path: "/tmp/DerivedData", bytes: 42))
        XCTAssertEqual(items[0].evidence, "du -sk /tmp/DerivedData")
    }

    func testTargetNameAlreadyEndingInCacheIsNotDuplicated() {
        let target = CacheCollector.Target(name: "User Cache", path: "/tmp/cache", risk: .caution)
        let items = CacheCollector.items(from: [
            CacheCollector.Measured(target: target, bytes: 1)
        ])

        XCTAssertEqual(items[0].title, "User Cache")
    }

    func testMinimumCacheSizeIsTwentyMegabytes() {
        XCTAssertEqual(CacheCollector.minimumBytes, 20 * 1024 * 1024)
    }

    func testEmptyMeasuredListProducesNoItems() {
        XCTAssertTrue(CacheCollector.items(from: []).isEmpty)
    }

    func testNestedCacheIsNotCountedTwice() {
        let general = CacheCollector.Measured(
            target: .init(name: "General", path: "/tmp/Caches", risk: .caution),
            bytes: 1_000 * 1024 * 1024
        )
        let homebrew = CacheCollector.Measured(
            target: .init(name: "Homebrew", path: "/tmp/Caches/Homebrew", risk: .safe),
            bytes: 100 * 1024 * 1024
        )

        let adjusted = CacheCollector.removingNestedOverlap([general, homebrew])

        XCTAssertEqual(adjusted.first { $0.target.name == "General" }?.bytes, 900 * 1024 * 1024)
        XCTAssertEqual(adjusted.first { $0.target.name == "Homebrew" }?.bytes, 100 * 1024 * 1024)
    }

    func testNestedOverlapDoesNotChangeUnrelatedCaches() {
        let xcode = CacheCollector.Measured(
            target: .init(name: "Xcode DerivedData", path: "/tmp/DerivedData", risk: .safe),
            bytes: 500 * 1024 * 1024
        )
        let general = CacheCollector.Measured(
            target: .init(name: "General", path: "/tmp/Caches", risk: .caution),
            bytes: 300 * 1024 * 1024
        )

        let adjusted = CacheCollector.removingNestedOverlap([xcode, general])

        XCTAssertEqual(adjusted.map(\.bytes), [500 * 1024 * 1024, 300 * 1024 * 1024])
    }

    func testDynamicCachesGetFriendlyNamesAndSkipNoise() {
        let caches = "/Users/tester/Library/Caches"
        let children = [
            PathSizer.ChildSize(path: "\(caches)/com.microsoft.VSCode.ShipIt", bytes: 1_500_000_000),
            PathSizer.ChildSize(path: "\(caches)/Google", bytes: 1_400_000_000),
            PathSizer.ChildSize(path: "\(caches)/Homebrew", bytes: 100_000_000),
            PathSizer.ChildSize(path: "\(caches)/.hidden", bytes: 90_000_000),
            PathSizer.ChildSize(path: "\(caches)/com.apple.foo", bytes: 90_000_000),
            PathSizer.ChildSize(path: "\(caches)/Tiny", bytes: 1_000_000)
        ]

        let measured = CacheCollector.dynamicMeasured(
            children: children,
            cachesPath: caches,
            excluding: ["\(caches)/Homebrew"]
        )

        XCTAssertEqual(measured.map(\.target.name), ["VSCode update", "Google Chrome"])
        XCTAssertEqual(measured.map(\.bytes), [1_500_000_000, 1_400_000_000])
        XCTAssertEqual(measured[0].target.relatedApps, ["code"])
        XCTAssertEqual(measured[1].target.relatedApps, ["google chrome"])
        XCTAssertEqual(measured[0].target.risk, .caution)
    }

    func testDynamicCacheWarningUsesFriendlyAppName() {
        let target = CacheCollector.Target(
            name: "Google Chrome",
            path: "/tmp/Google",
            risk: .caution,
            relatedApps: ["google chrome"]
        )
        let items = CacheCollector.items(
            from: [CacheCollector.Measured(target: target, bytes: 42)],
            running: ["google chrome"]
        )

        XCTAssertEqual(
            items[0].warning,
            "Google Chrome is running. Quit it before moving this cache to the Trash."
        )
    }
}
