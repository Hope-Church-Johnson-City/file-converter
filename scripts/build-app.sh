#!/bin/bash
# Builds "File Converter.app" into dist/. With --install, also copies it to /Applications.
#
# Signs with the Hope Church Developer ID when that certificate is in the
# keychain (hardened runtime, ready to notarize), and ad hoc otherwise.
# SIGN_IDENTITY=- forces ad hoc.
#
# The app carries its own copy of LAME (the MP3 encoder) and the one library
# it links, so it works on a Mac without Homebrew. Building it needs
# `brew install lame` on this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/File Converter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/FileConverter "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# LAME and mpg123 are LGPL; their licenses travel with the copies of them.
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$(brew --prefix lame)/COPYING" "$APP/Contents/Resources/Licenses/LAME.txt"
cp "$(brew --prefix mpg123)/COPYING" "$APP/Contents/Resources/Licenses/mpg123.txt"

LAME="$(brew --prefix lame)/bin/lame"
cp -L "$LAME" "$APP/Contents/MacOS/lame"
chmod u+w "$APP/Contents/MacOS/lame"
# Copy every Homebrew library LAME links and point LAME at the copies.
for lib in $(otool -L "$LAME" | awk 'NR > 1 && /\/opt\/homebrew|\/usr\/local/ {print $1}'); do
  name=$(basename "$lib")
  cp -L "$lib" "$APP/Contents/Frameworks/$name"
  chmod u+w "$APP/Contents/Frameworks/$name"
  install_name_tool -id "@rpath/$name" "$APP/Contents/Frameworks/$name"
  install_name_tool -change "$lib" "@executable_path/../Frameworks/$name" "$APP/Contents/MacOS/lame"
done

DEVELOPER_ID="Developer ID Application: Hope Church JC (TCAQTA64TB)"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if security find-identity -v -p codesigning | grep -q "$DEVELOPER_ID"; then
    SIGN_IDENTITY=$DEVELOPER_ID
  else
    SIGN_IDENTITY=-
  fi
fi
SIGN=(codesign -f -s "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && SIGN+=(--options runtime --timestamp)

# Inside out: the library, then LAME, then the app.
for f in "$APP/Contents/Frameworks/"*; do "${SIGN[@]}" "$f"; done
"${SIGN[@]}" "$APP/Contents/MacOS/lame"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $APP (signed: $SIGN_IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "File Converter"' 2>/dev/null || true
  rm -rf "/Applications/File Converter.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/File Converter.app"
fi
