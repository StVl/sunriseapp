#!/bin/bash
# Publishes build/Sunrise-<version>.dmg as GitHub release v<version>.
# The asset is uploaded as "Sunrise.dmg", so the landing page's download link
# (…/releases/latest/download/Sunrise.dmg) always serves the newest version.
#   ./scripts/make-dmg.sh && ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="build/Sunrise-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "No $DMG — run ./scripts/make-dmg.sh first"; exit 1; }

# Only notarized builds go public.
spctl --assess --type open --context context:primary-signature "$DMG" 2>/dev/null \
    || { echo "$DMG isn't notarized — refusing to publish"; exit 1; }

ASSET=$(mktemp -d)/Sunrise.dmg
cp "$DMG" "$ASSET"
gh release create "v$VERSION" "$ASSET" \
    --repo StVl/sunriseapp \
    --title "Sunrise $VERSION" \
    --notes "Sunrise $VERSION for macOS 14+ (Apple Silicon and Intel). Signed and notarized. 30-day free trial, then \$7 once."
echo "Released v$VERSION → https://github.com/StVl/sunriseapp/releases/latest/download/Sunrise.dmg"
