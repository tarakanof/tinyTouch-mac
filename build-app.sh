#!/bin/sh
# Builds dist/tinyTouch.app from the Swift package and ad-hoc signs it.
set -eu

cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  # SwiftUI macros ship with Xcode, not the Command Line Tools.
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

version="$(cat ../../VERSION 2>/dev/null || echo 0.0.0)"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=dist/tinyTouch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/TinyTouchApp" "$app/Contents/MacOS/TinyTouchApp"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"
codesign --force --sign - --options runtime "$app"

echo "Built $(pwd)/$app"
