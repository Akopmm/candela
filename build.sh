#!/bin/bash
# Build Cinema.app.
#   ./build.sh             dev build: uses Homebrew's mpv at runtime, installs to ~/Applications
#   ./build.sh --release   self-contained build: mpv + libraries bundled, zipped into dist/
# Needs the Xcode Command Line Tools and `brew install mpv`.
set -euo pipefail
cd "$(dirname "$0")"

RELEASE=0
[ "${1:-}" = "--release" ] && RELEASE=1

APP=build/Cinema.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework Security \
  Sources/*.swift -o "$APP/Contents/MacOS/Cinema"

cp Resources/Info.plist Resources/cinema.conf Resources/AppIcon.icns "$APP/Contents/" 2>/dev/null || true
mv "$APP/Contents/cinema.conf" "$APP/Contents/AppIcon.icns" "$APP/Contents/Resources/"

if [ $RELEASE = 1 ]; then
  python3 scripts/bundle_mpv.py "$APP"
  cp LICENSE THIRD_PARTY.md "$APP/Contents/Resources/"
fi

codesign --force --sign - "$APP"

if [ $RELEASE = 1 ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  mkdir -p dist
  rm -f "dist/Cinema-$VERSION-arm64.zip"
  ditto -c -k --keepParent "$APP" "dist/Cinema-$VERSION-arm64.zip"
  echo "Built dist/Cinema-$VERSION-arm64.zip"
else
  mkdir -p ~/Applications
  rm -rf ~/Applications/Cinema.app
  cp -R "$APP" ~/Applications/
  echo "Installed ~/Applications/Cinema.app"
fi
