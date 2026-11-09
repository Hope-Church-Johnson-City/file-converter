#!/bin/bash
# Builds "File Converter.app" into dist/. With --install, also copies it to /Applications.
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

# Ad-hoc signing, inside out. Fine for Macs it's built on; another Mac would
# need it signed with a Developer ID.
for f in "$APP/Contents/Frameworks/"*; do codesign -f -s - "$f"; done
codesign -f -s - "$APP/Contents/MacOS/lame"
codesign -f -s - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "File Converter"' 2>/dev/null || true
  rm -rf "/Applications/File Converter.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/File Converter.app"
fi
