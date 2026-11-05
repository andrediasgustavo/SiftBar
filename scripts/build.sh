#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SiftBar"
CONFIG="${1:-release}"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_DIR="$ROOT/dist/$APP_NAME.app"

case "$CONFIG" in
    release) OPT_FLAGS=(-O -whole-module-optimization) ;;
    debug)   OPT_FLAGS=(-Onone -g) ;;
    *)       echo "Unknown configuration: $CONFIG" >&2; exit 1 ;;
esac

SDK="$(xcrun --show-sdk-path)"
mkdir -p "$BUILD_DIR"

echo "==> Compiling ($CONFIG)"
# Direct swiftc build. The SwiftPM manifest loader shipped with this
# Command Line Tools installation fails to link PackageDescription, so the
# scripts bypass SwiftPM. Package.swift is kept for other toolchains.
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources/SiftBar" -name '*.swift' -print | sort)

xcrun swiftc \
    "${OPT_FLAGS[@]}" \
    -parse-as-library \
    -target arm64-apple-macos13.0 \
    -sdk "$SDK" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$BUILD_DIR/$APP_NAME" \
    "${SOURCES[@]}"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP_DIR" >/dev/null

echo "==> Done: $APP_DIR"
