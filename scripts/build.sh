#!/bin/bash
# Builds PinTop.app (Apple Silicon) into ./build.
#   scripts/build.sh            – build and sign
#   scripts/build.sh install    – also copy to /Applications and launch
# Set CODESIGN_IDENTITY to override the signing identity ("-" for ad-hoc).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP_NAME=PinTop
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling"
swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "==> Rendering app icon"
    TMP=$(mktemp -d)
    swiftc -O -o "$TMP/make-icon" "$ROOT/scripts/MakeIcon/main.swift" "$ROOT/Sources/PinTop/SVGPath.swift"
    "$TMP/make-icon" "$TMP/icon.png"
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
    rm -rf "$TMP"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Resources/Sounds" "$APP/Contents/Resources/Sounds"

# A stable signing identity keeps Accessibility / Screen Recording grants across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
echo "==> Signing with: $IDENTITY"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

if [[ "${1:-}" == "install" ]]; then
    echo "==> Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
fi

echo "==> Done: $APP"
