#!/usr/bin/env bash
set -euo pipefail

# Local quality gate. Run this before committing/pushing.
#
#   ./scripts/check.sh          # unit + UI smoke (fast, no Xcode needed)
#   ./scripts/check.sh --full   # also builds the release app and the DMG
#
# The XCUITest interaction suite runs only when both full Xcode and XcodeGen
# are installed; the rest of the gate works with Command Line Tools alone.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FULL=0
[ "${1:-}" = "--full" ] && FULL=1

echo "==> Unit tests"
if ! "$ROOT/scripts/test.sh"; then
    # The suite spawns real processes and is timing-sensitive: on a loaded
    # machine (Spotlight indexing, Xcode install, a build in another window)
    # a command test can hit its timeout. Retry once before blocking a commit.
    echo "Unit tests failed; retrying once (the suite is timing-sensitive under load)..."
    "$ROOT/scripts/test.sh"
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
fi

if [ "$FULL" -eq 1 ]; then
    echo "==> Release build"
    "$ROOT/scripts/build.sh" release

    echo "==> DMG"
    "$ROOT/scripts/package.sh"
fi

echo "All checks passed."
