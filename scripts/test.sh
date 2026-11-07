#!/usr/bin/env bash
set -euo pipefail

# Runs the XCTest suite without Xcode.app.
#
# This Command Line Tools installation has no XCTest.framework and its SwiftPM
# manifest loader cannot link PackageDescription, so `swift test` cannot run
# here. The script:
#   1. compiles a tiny XCTest-compatible module (Tests/Support/XCTestShim.swift);
#   2. compiles the app sources as a testable dynamic library;
#   3. generates a runner from every `func test...` in Tests/SiftBarTests;
#   4. runs the runner.
#
# CI with full Xcode still uses `swift test`; this is the local fallback.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/tests"
MODULES="$BUILD/modules"
LIBS="$BUILD/lib"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos13.0"

rm -rf "$BUILD"
mkdir -p "$MODULES" "$LIBS"

echo "==> Compiling XCTest shim"
xcrun swiftc \
    -parse-as-library \
    -emit-module -emit-library \
    -module-name XCTest \
    -target "$TARGET" \
    -sdk "$SDK" \
    -o "$LIBS/libXCTestShim.dylib" \
    -emit-module-path "$MODULES/XCTest.swiftmodule" \
    "$ROOT/Tests/Support/XCTestShim.swift"

echo "==> Compiling SiftBar module for tests"
APP_SOURCES=()
while IFS= read -r file; do
    APP_SOURCES+=("$file")
done < <(find "$ROOT/Sources/SiftBar" -name '*.swift' -print | sort)

xcrun swiftc \
    -parse-as-library \
    -emit-module -emit-library \
    -enable-testing \
    -module-name SiftBar \
    -target "$TARGET" \
    -sdk "$SDK" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$LIBS/libSiftBar.dylib" \
    -emit-module-path "$MODULES/SiftBar.swiftmodule" \
    "${APP_SOURCES[@]}"

echo "==> Generating test runner"
/usr/bin/python3 "$ROOT/scripts/generate-test-runner.py" \
    "$ROOT/Tests/SiftBarTests" \
    "$BUILD/GeneratedTests.swift"

TEST_SOURCES=()
while IFS= read -r file; do
    TEST_SOURCES+=("$file")
done < <(find "$ROOT/Tests/SiftBarTests" -name '*.swift' -print | sort)

echo "==> Compiling tests"
xcrun swiftc \
    -parse-as-library \
    -target "$TARGET" \
    -sdk "$SDK" \
    -I "$MODULES" \
    -L "$LIBS" \
    -lSiftBar -lXCTestShim \
    -Xlinker -rpath -Xlinker "$LIBS" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$BUILD/SiftBarTests" \
    "$BUILD/GeneratedTests.swift" \
    "${TEST_SOURCES[@]}"

echo "==> Running tests"
"$BUILD/SiftBarTests"
