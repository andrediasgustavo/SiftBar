import Foundation

// A tiny XCTest-compatible surface for Command Line Tools installations that
// ship without Xcode.app (and therefore without XCTest.framework).
//
// The real app and test sources are unchanged: this module is only used by
// scripts/test.sh, which compiles it as a module named `XCTest`. CI with full
// Xcode keeps using Apple's XCTest.

public struct XCTestFailure: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum XCTestRecorder {
    private static let lock = NSLock()
    private static var failures: [String] = []
    private static var passes = 0

    public static func recordFailure(_ message: String, file: StaticString, line: UInt) {
        lock.lock()
        defer { lock.unlock() }
        let location = "\(file):\(line)"
        failures.append("\(location): \(message)")
        print("  ✗ \(message)  (\(location))")
    }

    public static func recordPass() {
        lock.lock()
        defer { lock.unlock() }
        passes += 1
    }

    public static func summary() -> (passed: Int, failures: [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (passes, failures)
    }

    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        failures.removeAll()
        passes = 0
    }
}

open class XCTestCase {
    private var teardownBlocks: [() -> Void] = []

    public init() {}

    open func setUp() {}
    open func tearDown() {}

    public func addTeardownBlock(_ block: @escaping () -> Void) {
        teardownBlocks.append(block)
    }

    public func runTeardownBlocks() {
        for block in teardownBlocks.reversed() {
            block()
        }
        teardownBlocks.removeAll()
    }
}

public func XCTFail(
    _ message: String = "failed",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTestRecorder.recordFailure(message, file: file, line: line)
}

private func pass() {
    XCTestRecorder.recordPass()
}

public func XCTAssertTrue(
    _ expression: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if expression() {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure("XCTAssertTrue failed\(suffix)", file: file, line: line)
    }
}

public func XCTAssertFalse(
    _ expression: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if !expression() {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure("XCTAssertFalse failed\(suffix)", file: file, line: line)
    }
}

public func XCTAssertEqual<T: Equatable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if left == right {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertEqual failed: \(String(describing: left)) != \(String(describing: right))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertNotEqual<T: Equatable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if left != right {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertNotEqual failed: both are \(String(describing: left))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertEqual<T: FloatingPoint>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    accuracy: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if abs(left - right) <= accuracy {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertEqual failed: \(String(describing: left)) != \(String(describing: right)) (±\(accuracy))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertNil<T>(
    _ expression: @autoclosure () -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if expression() == nil {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure("XCTAssertNil failed\(suffix)", file: file, line: line)
    }
}

public func XCTAssertNotNil<T>(
    _ expression: @autoclosure () -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if expression() != nil {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure("XCTAssertNotNil failed\(suffix)", file: file, line: line)
    }
}

public func XCTAssertGreaterThan<T: Comparable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if left > right {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertGreaterThan failed: \(String(describing: left)) <= \(String(describing: right))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if left >= right {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertGreaterThanOrEqual failed: \(String(describing: left)) < \(String(describing: right))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertLessThan<T: Comparable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if left < right {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertLessThan failed: \(String(describing: left)) >= \(String(describing: right))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertLessThanOrEqual<T: Comparable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let left = lhs()
    let right = rhs()
    if left <= right {
        pass()
    } else {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertLessThanOrEqual failed: \(String(describing: left)) > \(String(describing: right))\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTAssertThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) {
    do {
        _ = try expression()
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure("XCTAssertThrowsError failed: did not throw\(suffix)", file: file, line: line)
    } catch {
        pass()
        errorHandler(error)
    }
}

public func XCTAssertNoThrow<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        _ = try expression()
        pass()
    } catch {
        let suffix = message().isEmpty ? "" : " — \(message())"
        XCTestRecorder.recordFailure(
            "XCTAssertNoThrow failed: threw \(error)\(suffix)",
            file: file,
            line: line
        )
    }
}

public func XCTUnwrap<T>(
    _ expression: @autoclosure () throws -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    if let value = try expression() {
        pass()
        return value
    }

    let suffix = message().isEmpty ? "" : " — \(message())"
    let failure = XCTestFailure(message: "XCTUnwrap failed: value was nil\(suffix)")
    XCTestRecorder.recordFailure(failure.message, file: file, line: line)
    throw failure
}
