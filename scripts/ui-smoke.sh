#!/usr/bin/env bash
set -euo pipefail

# UI smoke tests without Xcode or screen-recording permissions.
#
# The harness links the app sources as a library, hosts the SwiftUI views in
# real NSWindows, renders each window to a bitmap with Core Animation and runs
# Vision OCR over the pixels. Assertions cover the text users must see, the
# single primary action on the first-run screen, and the right-aligned risk
# label in a row.
#
# Usage:
#   ./scripts/ui-smoke.sh              # all scenarios
#   ./scripts/ui-smoke.sh item-row     # one scenario
#   ./scripts/ui-smoke.sh --keep       # keep the built harness for debugging

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/ui-smoke"
MODULES="$BUILD/modules"
LIBS="$BUILD/lib"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos13.0"

SCENARIOS=(first-run first-run-access menu overview item-row)

KEEP=0
ONLY=""
for arg in "$@"; do
    case "$arg" in
        --keep) KEEP=1 ;;
        *) ONLY="$arg" ;;
    esac
done

if [ -n "$ONLY" ] && [[ ! " ${SCENARIOS[*]} " == *" $ONLY "* ]]; then
    echo "Unknown scenario: $ONLY" >&2
    echo "Available: ${SCENARIOS[*]}" >&2
    exit 2
fi

rm -rf "$BUILD"
mkdir -p "$MODULES" "$LIBS"

echo "==> Compiling SiftBar module for UI tests"
APP_SOURCES=()
while IFS= read -r file; do
    APP_SOURCES+=("$file")
done < <(find "$ROOT/Sources/SiftBar" -name '*.swift' -print | sort)

xcrun swiftc \
    -parse-as-library \
    -emit-module -emit-library \
    -enable-testing \
    -module-name SiftBar \
    -D SIFTBAR_DEMO \
    -target "$TARGET" \
    -sdk "$SDK" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$LIBS/libSiftBar.dylib" \
    -emit-module-path "$MODULES/SiftBar.swiftmodule" \
    "${APP_SOURCES[@]}"

echo "==> Compiling UI smoke harness"
xcrun swiftc \
    -target "$TARGET" \
    -sdk "$SDK" \
    -I "$MODULES" \
    -L "$LIBS" \
    -lSiftBar \
    -Xlinker -rpath -Xlinker "$LIBS" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Vision \
    -o "$BUILD/SiftBarUISmoke" \
    "$ROOT/Tests/UITests/main.swift"

echo "==> Running UI smoke tests"
FAILED=0
if [ -n "$ONLY" ]; then
    "$BUILD/SiftBarUISmoke" "$ONLY" || FAILED=1
else
    for scenario in "${SCENARIOS[@]}"; do
        "$BUILD/SiftBarUISmoke" "$scenario" || FAILED=1
    done
fi

if [ "$KEEP" -eq 0 ]; then
    rm -rf "$BUILD"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "UI smoke tests failed." >&2
    exit 1
fi

echo "UI smoke tests passed."
