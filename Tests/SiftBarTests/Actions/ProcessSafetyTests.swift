import XCTest
@testable import SiftBar

final class ProcessSafetyTests: XCTestCase {
    private func entry(
        pid: Int32 = 100,
        user: String = "andre",
        command: String = "/Applications/Sample.app/Contents/MacOS/Sample",
        name: String? = nil
    ) -> ProcessCollector.Entry {
        ProcessCollector.Entry(
            pid: pid,
            user: user,
            bytes: 200 * 1024 * 1024,
            command: name.map { "/tmp/\($0)" } ?? command
        )
    }

    func testPIDZeroAndOneAreProtected() {
        XCTAssertTrue(ProcessSafety.isProtected(pid: 0, user: "andre", command: "/bin/test", name: "test"))
        XCTAssertTrue(ProcessSafety.isProtected(pid: 1, user: "root", command: "/sbin/launchd", name: "launchd"))
    }

    func testCriticalProcessNamesAreProtected() {
        for name in ["kernel_task", "launchd", "WindowServer", "loginwindow", "Dock", "Finder", "mds"] {
            XCTAssertTrue(
                ProcessSafety.isProtected(pid: 500, user: "andre", command: "/tmp/\(name)", name: name),
                "\(name) should be protected"
            )
        }
    }

    func testRootOwnedProcessesAreProtected() {
        XCTAssertTrue(
            ProcessSafety.isProtected(pid: 200, user: "root", command: "/opt/vendor/daemon", name: "daemon")
        )
    }

    func testSystemBinaryPathsAreProtected() {
        for path in [
            "/System/Library/CoreServices/thing",
            "/usr/libexec/thing",
            "/usr/sbin/thing",
            "/sbin/thing",
            "/Library/Apple/System/Library/thing"
        ] {
            XCTAssertTrue(
                ProcessSafety.isProtected(pid: 300, user: "andre", command: path, name: "thing"),
                "\(path) should be protected"
            )
        }
    }

    func testUserApplicationsAreNotProtected() {
        XCTAssertFalse(
            ProcessSafety.isProtected(
                pid: 400,
                user: "andre",
                command: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                name: "Google Chrome"
            )
        )
        XCTAssertFalse(
            ProcessSafety.isProtected(
                pid: 401,
                user: "andre",
                command: "/opt/homebrew/bin/opencode",
                name: "opencode"
            )
        )
    }

    func testUsrBinIsNotBlanketProtected() {
        XCTAssertFalse(
            ProcessSafety.isProtected(pid: 402, user: "andre", command: "/usr/bin/python3", name: "python3")
        )
    }

    func testEntryHelperUsesEntryFields() {
        let safe = entry()
        let unsafe = entry(user: "root", command: "/opt/vendor/daemon")

        XCTAssertFalse(ProcessSafety.isProtected(safe))
        XCTAssertTrue(ProcessSafety.isProtected(unsafe))
    }
}
