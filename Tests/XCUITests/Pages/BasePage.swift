import XCTest

/// Shared element lookup for the page objects.
///
/// SwiftUI exposes the visible string as the element's `value` (the
/// accessibility label is often empty or set on a parent), and link-styled
/// buttons surface as `link` elements on macOS. The helpers below cover both.
struct BasePage {
    let app: XCUIApplication

    func require(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "element not found: \(element)",
            file: file,
            line: line
        )
        return element
    }

    /// Matches a static text by its visible content, label or value.
    func staticText(_ needle: String, timeout: TimeInterval = 10) -> XCUIElement {
        require(
            app.staticTexts.matching(
                NSPredicate(format: "label == %@ OR value == %@", needle, needle)
            ).firstMatch,
            timeout: timeout
        )
    }

    /// Matches a static text whose content contains the needle.
    func textContaining(_ needle: String, timeout: TimeInterval = 10) -> XCUIElement {
        require(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", needle, needle)
            ).firstMatch,
            timeout: timeout
        )
    }

    /// Link-styled buttons are exposed as `link` on macOS; this prefers the
    /// link and falls back to a button, by identifier.
    func linkOrButton(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement {
        let link = app.links[identifier]
        if link.exists { return link }
        return require(app.buttons[identifier], timeout: timeout)
    }

    /// Menus and pickers keep working even when SwiftUI moves the identifier
    /// to a parent element or exposes the control under a different element
    /// type on another OS/SDK. Look the control up by identifier first (in
    /// every query), then by its visible label.
    func control(_ queries: [XCUIElementQuery], identifier: String, label: String, timeout: TimeInterval = 10) -> XCUIElement {
        for query in queries {
            let byId = query[identifier]
            if byId.waitForExistence(timeout: 1) { return byId }
        }

        for query in queries {
            let byLabel = query[label]
            if byLabel.waitForExistence(timeout: 1) { return byLabel }
        }

        // Let require() produce a useful failure message.
        return queries[0][identifier]
    }

    func assertLabel(_ element: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(element.label, expected, file: file, line: line)
    }

    func assertValueContains(_ element: XCUIElement, _ needle: String, file: StaticString = #filePath, line: UInt = #line) {
        let value = element.value as? String ?? ""
        XCTAssertTrue(value.contains(needle), "expected value to contain '\(needle)', got '\(value)'", file: file, line: line)
    }
}
