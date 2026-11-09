#!/bin/bash
# Builds a signed, notarized "File-Converter-<version>.dmg" in dist/ and, with
# --publish, makes it a GitHub release. The CMS Downloads page checks this repo
# every 15 minutes and copies the newest release's .dmg (docs/cms/DOWNLOADS.md
# in hope-media-automation), so publishing is all a new version needs.
#
#   scripts/release.sh             # build and notarize only
#   scripts/release.sh --publish   # and create the GitHub release v<version>
#
# The version is CFBundleShortVersionString in Resources/Info.plist; bump it
# (and CFBundleVersion) first. Needs the Developer ID certificate and the App
# Store Connect key Hope Church for Mac notarizes with.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=${NOTARY_KEY_ID:-SN9Q4M95MW}
ISSUER=${NOTARY_ISSUER:-a08350fb-7f69-4c38-8b7c-ea62542feae5}
KEY_PATH=${NOTARY_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}
REPO=Hope-Church-Johnson-City/file-converter

[[ -f $KEY_PATH ]] || { echo "Missing notary key at $KEY_PATH" >&2; exit 1; }

notarize() {
  local file=$1 out id
  out=$(xcrun notarytool submit "$file" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" --wait --output-format json)
  echo "$out"
  id=$(echo "$out" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  if ! echo "$out" | grep -q '"status" *: *"Accepted"'; then
    xcrun notarytool log "$id" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER"
    exit 1
  fi
}

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="dist/File Converter.app"
DMG="dist/File-Converter-$VERSION.dmg"

echo "== Build $VERSION"
unset SIGN_IDENTITY
./scripts/build-app.sh
codesign -dv "$APP" 2>&1 | grep -q "TeamIdentifier=TCAQTA64TB" \
  || { echo "The app isn't signed with the Hope Church Developer ID" >&2; exit 1; }

echo "== Notarize the app"
# Stapled on its own as well as inside the DMG, so it opens offline once copied.
rm -f dist/app.zip
ditto -c -k --keepParent "$APP" dist/app.zip
notarize dist/app.zip
xcrun stapler staple "$APP"
rm -f dist/app.zip

echo "== DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "File Converter" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
codesign -f -s "Developer ID Application: Hope Church JC (TCAQTA64TB)" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Built $DMG"

if [[ "${1:-}" == "--publish" ]]; then
  echo "== GitHub release v$VERSION"
  # The org repo needs the cowens-cmyk account; the keychain's other GitHub
  # login can't see it.
  GH_TOKEN=$(gh auth token --user cowens-cmyk) gh release create "v$VERSION" "$DMG" \
    --repo "$REPO" --title "File Converter $VERSION" --notes-file <(git log -1 --format=%B | sed '/^Co-Authored-By/d')
fi
