import XCTest
@testable import SiftBar

final class RunningProcessesTests: XCTestCase {
    func testParseReturnsLowercasedExecutableNames() {
        let output = """
        /Applications/Xcode.app/Contents/MacOS/Xcode
        /usr/libexec/foo
         /bin/Bar
        """

        XCTAssertEqual(RunningProcesses.parse(output), ["xcode", "foo", "bar"])
    }

    func testParseSkipsEmptyLines() {
        XCTAssertTrue(RunningProcesses.parse("\n\n   \n").isEmpty)
        XCTAssertTrue(RunningProcesses.parse("").isEmpty)
    }
}
