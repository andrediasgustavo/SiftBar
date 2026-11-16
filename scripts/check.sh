#!/usr/bin/env bash
set -euo pipefail

# Full local quality gate. The pre-commit hook intentionally runs unit tests
# only; use this when you want the UI suite locally too.
#
#   ./scripts/check.sh            # unit + XCUITest
#   ./scripts/check.sh --ui-only  # XCUITest only
#   ./scripts/check.sh --full     # unit + UI + release app + DMG
#
# The XCUITest interaction suite runs only when both full Xcode and XcodeGen
# are installed; the rest of the gate works with Command Line Tools alone.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FULL=0
UI_ONLY=0
for argument in "$@"; do
    case "$argument" in
        --full) FULL=1 ;;
        --ui-only) UI_ONLY=1 ;;
        *)
            echo "Unknown argument: $argument" >&2
            exit 2
            ;;
    esac
done

if [ "$UI_ONLY" -eq 0 ]; then
    echo "==> Unit tests"
    if ! "$ROOT/scripts/test.sh"; then
        # The suite spawns real processes and is timing-sensitive: on a loaded
        # machine (Spotlight indexing, Xcode install, a build in another window)
        # a command test can hit its timeout. Retry once before blocking a commit.
        echo "Unit tests failed; retrying once (the suite is timing-sensitive under load)..."
        "$ROOT/scripts/test.sh"
    fi
fi

if xcodebuild -version >/dev/null 2>&1 && command -v xcodegen >/dev/null 2>&1; then
    echo "==> XCUITest (interaction)"
    (
        cd "$ROOT"
        xcodegen generate >/dev/null
        rm -rf "$ROOT/.build/UI.xcresult"
        if ! xcodebuild test \
            -project SiftBar.xcodeproj \
            -scheme SiftBar \
            -destination 'platform=macOS' \
            -resultBundlePath "$ROOT/.build/UI.xcresult" \
            > "$ROOT/.build/xcuitest.log" 2>&1; then
            tail -60 "$ROOT/.build/xcuitest.log" >&2
            exit 1
        fi
    )
else
    echo "==> XCUITest skipped (needs full Xcode and XcodeGen)"
    if [ "$UI_ONLY" -eq 1 ]; then
        echo "UI-only run cannot proceed without Xcode and XcodeGen." >&2
        exit 1
    fi
fi

if [ "$FULL" -eq 1 ]; then
    echo "==> Release build"
    "$ROOT/scripts/build.sh" release

    echo "==> DMG"
    "$ROOT/scripts/package.sh"
fi

echo "All checks passed."
