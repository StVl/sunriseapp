#!/bin/bash
# Builds a universal Sunrise.app and packs it into build/Sunrise-<version>.dmg
# with an Applications shortcut and install notes.
#
# Signing is automatic:
#   - a "Developer ID Application" certificate in the keychain → signed for distribution;
#   - plus a notarytool keychain profile (default "sunrise", override with NOTARY_PROFILE)
#     → notarized and stapled: opens anywhere without Gatekeeper warnings.
#   Otherwise the DMG is ad-hoc signed (recipients need `xattr -dr com.apple.quarantine`).
#   One-time setup:  xcrun notarytool store-credentials sunrise --apple-id … --team-id …
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
NOTARY_PROFILE="${NOTARY_PROFILE:-sunrise}"

if [[ -n "$IDENTITY" ]]; then
    echo "Signing with: $IDENTITY"
    SIGN_IDENTITY="$IDENTITY" UNIVERSAL=1 ./scripts/build-app.sh
else
    echo "No Developer ID certificate — ad-hoc signing."
    UNIVERSAL=1 ./scripts/build-app.sh
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="build/Sunrise-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Sunrise.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/DMG-README.txt "$STAGE/READ ME FIRST.txt"

rm -f "$DMG"
hdiutil create -volname "Sunrise" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [[ -z "$IDENTITY" ]]; then
    echo "Built $DMG ($(du -h "$DMG" | cut -f1)) — ad-hoc signed, not notarized"
    exit 0
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Built $DMG ($(du -h "$DMG" | cut -f1)) — signed, NOT notarized (no notarytool profile \"$NOTARY_PROFILE\")"
    exit 0
fi

echo "Notarizing (usually 1–10 min)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "Built $DMG ($(du -h "$DMG" | cut -f1)) — signed, notarized, stapled"
