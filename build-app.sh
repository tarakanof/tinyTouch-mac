#!/bin/sh
# Builds dist/tinyTouch.app from the Swift package and ad-hoc signs it.
set -eu

cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  # SwiftUI macros ship with Xcode, not the Command Line Tools.
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

version="$(cat ../../VERSION 2>/dev/null || echo 0.0.0)"
# CFBundleShortVersionString allows only numbers and dots.
version="${version%%-*}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=dist/tinyTouch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/TinyTouchApp" "$app/Contents/MacOS/TinyTouchApp"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"
# A team identity keeps the menu bar permission valid wherever the app is installed;
# macOS tracks ad-hoc signed apps by path.
identity="${SIGN_IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null |
  awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"
codesign --force --sign "${identity:--}" --options runtime --timestamp=none "$app"
echo "Signed with: ${identity:-ad-hoc}"

echo "Built $(pwd)/$app"
