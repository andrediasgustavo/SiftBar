#!/usr/bin/env python3
"""Generates a main that runs every XCTestCase method in a directory.

The Command Line Tools installation used by this project has no XCTest
framework, so scripts/test.sh pairs Apple's test sources with a small shim.
This generator keeps the runner in sync with the test files automatically.
"""

import pathlib
import re
import sys

TEST_FUNCTION = re.compile(
    r"^\s{4}func\s+(test\w+)\s*\(\)\s*(?:(async)\s*)?(?:(throws)\s*)?\{",
    re.MULTILINE,
)
TEST_CLASS = re.compile(r"^(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b", re.MULTILINE)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: generate-test-runner.py <tests-dir> <output.swift>", file=sys.stderr)
        return 2

    tests_dir = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])

    entries = []
    for path in sorted(tests_dir.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        classes = TEST_CLASS.findall(text)
        if not classes:
            continue
        if len(classes) != 1:
            raise SystemExit(f"{path}: expected exactly one XCTestCase class, found {classes}")

        class_name = classes[0]
        methods = TEST_FUNCTION.findall(text)
        if not methods:
            continue

        for method, _async, _throws in methods:
            entries.append((class_name, method))

    if not entries:
        raise SystemExit("No test methods found.")

    lines = [
        "import Foundation",
        "import XCTest",
        "@testable import SiftBar",
        "",
        "struct GeneratedTest {",
        "    let name: String",
        "    let run: () async throws -> Void",
        "}",
        "",
        "@main",
        "struct SiftBarTestRunner {",
        "    static func main() async {",
        "        let tests: [GeneratedTest] = [",
    ]

    for index, (class_name, method) in enumerate(entries):
        name = f"{class_name}.{method}"
        lines.extend([
            "            GeneratedTest(name: \"%s\") {" % name,
            f"                let test = {class_name}()",
            "                test.setUp()",
            "                defer {",
            "                    test.runTeardownBlocks()",
            "                    test.tearDown()",
            "                }",
            "                do {",
            f"                    try await test.{method}()",
            "                } catch {",
            "                    XCTFail(\"threw \\(error)\", file: #filePath, line: #line)",
            "                }",
            "            },",
        ])
        if index != len(entries) - 1:
            pass

    lines.extend([
        "        ]",
        "",
        "        var failedTests = 0",
        "        for test in tests {",
        "            let before = XCTestRecorder.summary().failures.count",
        "            do {",
        "                try await test.run()",
        "            } catch {",
        "                XCTFail(\"threw \\(error)\", file: #filePath, line: #line)",
        "            }",
        "            let after = XCTestRecorder.summary().failures.count",
        "            if after == before {",
        "                print(\"✓ \\(test.name)\")",
        "            } else {",
        "                failedTests += 1",
        "                print(\"✗ \\(test.name)\")",
        "            }",
        "        }",
        "",
        "        let summary = XCTestRecorder.summary()",
        "        print(\"\")",
        "        print(\"\\(tests.count - failedTests)/\\(tests.count) tests passed · \\(summary.passed) assertions\")",
        "        if failedTests > 0 {",
        "            print(\"\\(summary.failures.count) assertion failure(s):\")",
        "            for failure in summary.failures {",
        "                print(\"  - \\(failure)\")",
        "            }",
        "            exit(1)",
        "        }",
        "    }",
        "}",
        "",
    ])

    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"    {len(entries)} tests from {len({entry[0] for entry in entries})} classes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
