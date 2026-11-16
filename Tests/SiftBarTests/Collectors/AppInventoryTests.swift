import XCTest
@testable import SiftBar

final class AppInventoryTests: XCTestCase {
    private func inventory(
        apps: [AppInventory.App] = [],
        receipts: [String] = [],
        caskTokens: [String] = [],
        isIncomplete: Bool = false
    ) -> AppInventory {
        AppInventory(
            apps: apps,
            receipts: receipts,
            caskTokens: caskTokens,
            isIncomplete: isIncomplete
        )
    }

    func testAppNameOwnsAnApplicationSupportFolder() {
        let index = inventory(apps: [
            .init(name: "Google Chrome", path: "/Applications/Google Chrome.app", source: .applications)
        ])

        XCTAssertEqual(index.ownership(for: "Google"), .owned)
        XCTAssertEqual(index.ownership(for: "Chrome"), .owned)
        XCTAssertEqual(index.ownership(for: "OrphanApp"), .none)
    }

    func testBundleIDAndLastComponentOwnAFolder() {
        let index = inventory(apps: [
            .init(
                name: "CLion",
                bundleID: "com.jetbrains.CLion",
                path: "/Applications/CLion.app",
                source: .applications
            )
        ])

        XCTAssertEqual(index.ownership(for: "com.jetbrains.CLion"), .owned)
        XCTAssertEqual(index.ownership(for: "CLion"), .owned)
    }

    func testCaskTokenOwnsAFolder() {
        let index = inventory(caskTokens: ["visual-studio-code"])

        XCTAssertEqual(index.ownership(for: "Visual Studio Code"), .owned)
        XCTAssertEqual(index.ownership(for: "visual studio code"), .owned)
    }

    func testReceiptOwnsAFolderByLastComponent() {
        let index = inventory(receipts: ["com.example.OrphanTool"])

        XCTAssertEqual(index.ownership(for: "OrphanTool"), .owned)
    }

    func testVendorIdentifierOnlyDowngradesFolders() {
        let index = inventory(apps: [
            .init(
                name: "CLion",
                bundleID: "com.jetbrains.CLion",
                path: "/Applications/CLion.app",
                source: .applications
            )
        ])

        XCTAssertEqual(index.ownership(for: "JetBrains"), .vendor)
        XCTAssertEqual(index.vendorIdentifier(for: "JetBrains"), "jetbrains")
        XCTAssertNil(index.vendorIdentifier(for: "SomethingElse"))
    }

    func testInvalidVendorTokensAreIgnored() {
        XCTAssertTrue(AppInventory.vendorTokens(bundleID: "com.foo.Bar").isEmpty)
        XCTAssertTrue(AppInventory.vendorTokens(bundleID: "com.apple.Safari").isEmpty)
        XCTAssertEqual(AppInventory.vendorTokens(bundleID: "com.jetbrains.CLion"), ["jetbrains"])
    }

    func testShortFolderNamesAreTreatedAsOwned() {
        let index = inventory()

        XCTAssertEqual(index.ownership(for: "ab"), .owned)
        XCTAssertEqual(index.ownership(for: "x"), .owned)
    }

    func testSpotlightNoisePathsAreIgnored() {
        XCTAssertTrue(AppInventory.isNoisePath("/System/Library/CoreServices/Finder.app"))
        XCTAssertTrue(AppInventory.isNoisePath("/Users/me/Library/Caches/Foo.app"))
        XCTAssertTrue(AppInventory.isNoisePath("/Users/me/.Trash/Old.app"))
        XCTAssertTrue(AppInventory.isNoisePath("/Volumes/Backup/App.app"))
        XCTAssertFalse(AppInventory.isNoisePath("/Users/me/Desktop/Portable.app"))
    }

    func testIncompleteInventoryIsReported() {
        XCTAssertTrue(inventory(isIncomplete: true).isIncomplete)
        XCTAssertFalse(inventory().isIncomplete)
    }
}
