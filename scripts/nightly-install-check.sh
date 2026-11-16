#!/usr/bin/env bash
set -euo pipefail

# Nightly release-shape check: build the real bundle and DMG, verify the
# universal binary and deployment target, mount the DMG, and simulate an
# upgrade over the previous release in a temporary Applications folder.
#
# This does not install into /Applications and does not touch TCC/FDA; those
# require a disposable Mac user or VM. Run locally with:
#   ./scripts/nightly-install-check.sh [previous-tag]
# Default previous tag: v0.6.0.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIOUS_TAG="${1:-v0.6.0}"
WORK="$(mktemp -d)"
MOUNT_NEW="$WORK/new"
MOUNT_OLD="$WORK/old"
TEMP_APPS="$WORK/Applications"
trap 'hdiutil detach "$MOUNT_NEW" >/dev/null 2>&1 || true; hdiutil detach "$MOUNT_OLD" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

echo "==> Build universal release"
ARCHS="arm64 x86_64" "$ROOT/scripts/build.sh" release >/dev/null
"$ROOT/scripts/package.sh" >/dev/null

APP="$ROOT/dist/SiftBar.app"
DMG="$ROOT/dist/SiftBar.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"

test -f "$DMG"
echo "==> App: $VERSION ($BUILD), universal, min macOS 13"

file "$APP/Contents/MacOS/SiftBar" | grep -q "universal binary" \
    || { echo "not a universal binary" >&2; exit 1; }
file "$APP/Contents/MacOS/SiftBar" | grep -q "x86_64" \
    || { echo "x86_64 slice missing" >&2; exit 1; }
file "$APP/Contents/MacOS/SiftBar" | grep -q "arm64" \
    || { echo "arm64 slice missing" >&2; exit 1; }
# The workspace may live in iCloud Drive; FinderInfo/fileprovider xattrs make
# strict verification fail even though the code signature is valid.
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" >/dev/null 2>&1

MINOS="$(xcrun vtool -show-build "$APP/Contents/MacOS/SiftBar" | awk '/minos/{print $2; exit}')"
test "$MINOS" = "13.0" || { echo "unexpected minos: $MINOS" >&2; exit 1; }

mkdir -p "$MOUNT_NEW" "$MOUNT_OLD" "$TEMP_APPS"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_NEW" >/dev/null
test -L "$MOUNT_NEW/Applications"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_NEW/SiftBar.app/Contents/Info.plist")" = "$VERSION"
codesign --verify --deep --strict "$MOUNT_NEW/SiftBar.app"

echo "==> Simulate upgrade from $PREVIOUS_TAG"
PREVIOUS_DMG="$WORK/previous.dmg"
curl --fail --silent --show-error --location \
    "https://github.com/andrediasgustavo/SiftBar/releases/download/$PREVIOUS_TAG/SiftBar.dmg" \
    -o "$PREVIOUS_DMG"
hdiutil attach "$PREVIOUS_DMG" -nobrowse -readonly -mountpoint "$MOUNT_OLD" >/dev/null

OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_OLD/SiftBar.app/Contents/Info.plist")"
test "$OLD_VERSION" != "$VERSION" || { echo "previous and current versions are equal" >&2; exit 1; }
codesign --verify --deep --strict "$MOUNT_OLD/SiftBar.app"

ditto --noextattr --norsrc "$MOUNT_OLD/SiftBar.app" "$TEMP_APPS/SiftBar.app"
ditto --noextattr --norsrc --noqtn "$APP" "$TEMP_APPS/SiftBar.app"
xattr -cr "$TEMP_APPS/SiftBar.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TEMP_APPS/SiftBar.app/Contents/Info.plist")" = "$VERSION"
codesign --verify --deep --strict "$TEMP_APPS/SiftBar.app"

echo "==> Install/upgrade shape OK: $OLD_VERSION -> $VERSION"
