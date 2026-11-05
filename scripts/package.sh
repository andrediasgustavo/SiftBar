#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SiftBar"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"

if [ ! -d "$APP" ]; then
    echo "Missing $APP. Run ./scripts/build.sh release first." >&2
    exit 1
fi

# Stage outside the repo: iCloud-synced folders can reattach Finder metadata
# to the staged app, which makes codesign verification fail inside the image.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/root"
SOURCE="$STAGING/root"
IMAGE="$STAGING/$APP_NAME.dmg"

echo "==> Staging $APP_NAME.app"
COPYFILE_DISABLE=1 cp -R "$APP" "$SOURCE/"
ln -s /Applications "$SOURCE/Applications"

xattr -cr "$SOURCE" 2>/dev/null || true

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$SOURCE" \
    -ov \
    -format UDZO \
    -fs APFS \
    "$IMAGE" >/dev/null

echo "==> Verifying DMG"
hdiutil verify "$IMAGE" >/dev/null

mkdir -p "$ROOT/dist"
mv -f "$IMAGE" "$DMG"

echo "==> Done: $DMG"
du -h "$DMG"
