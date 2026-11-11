#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SiftBar"
CONFIG="${1:-release}"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_DIR="$ROOT/dist/$APP_NAME.app"

case "$CONFIG" in
    release) OPT_FLAGS=(-O -whole-module-optimization) ;;
    demo)    OPT_FLAGS=(-O -whole-module-optimization -D SIFTBAR_DEMO) ;;
    debug)   OPT_FLAGS=(-Onone -g -D SIFTBAR_DEMO) ;;
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

# Universal binary by default so the app also runs on Intel Macs. Override
# with ARCHS="arm64" for a faster local build.
ARCH_LIST=(${ARCHS:-arm64 x86_64})
BINARIES=()
for arch in "${ARCH_LIST[@]}"; do
    echo "    - $arch"
    xcrun swiftc \
        "${OPT_FLAGS[@]}" \
        -parse-as-library \
        -target "$arch-apple-macos13.0" \
        -sdk "$SDK" \
        -framework SwiftUI \
        -framework AppKit \
        -o "$BUILD_DIR/$APP_NAME-$arch" \
        "${SOURCES[@]}"
    BINARIES+=("$BUILD_DIR/$APP_NAME-$arch")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$BUILD_DIR/$APP_NAME"
else
    xcrun lipo -create "${BINARIES[@]}" -output "$BUILD_DIR/$APP_NAME"
fi
rm -f "${BINARIES[@]}"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP_DIR" >/dev/null

echo "==> Done: $APP_DIR"
