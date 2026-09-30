#!/bin/bash
# Builds Sunrise.app into ./build.
#   ./scripts/build-app.sh              release, this Mac's architecture, ad-hoc signed
#   UNIVERSAL=1 ./scripts/build-app.sh  release, arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
#                                       signed for distribution (hardened runtime, timestamp)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BINARY=".build/apple/Products/Release/Sunrise"
else
    swift build -c release
    BINARY=".build/release/Sunrise"
fi

APP="build/Sunrise.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Sunrise"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon: Tahoe-style icon (Assets.car, from Sunrise.icon) + classic Sunrise.icns for macOS 14–15.
ICON_TMP=$(mktemp -d)
trap 'rm -rf "$ICON_TMP"' EXIT
xcrun actool Resources/Icon/Sunrise.icon --compile "$ICON_TMP" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon Sunrise \
    --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null
cp "$ICON_TMP/Assets.car" "$APP/Contents/Resources/"
ICONSET="$ICON_TMP/Sunrise.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/Icon/icon-classic-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/Icon/icon-classic-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Sunrise.icns"
# Icon tools leave Finder metadata that codesign rejects.
xattr -cr "$APP"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --entitlements Resources/Sunrise.entitlements "$APP" >/dev/null
else
    # Notarization needs the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp \
        --entitlements Resources/Sunrise.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Sunrise"))"
