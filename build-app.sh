#!/bin/sh
# Builds dist/tinyTouch.app with the tinytouch CLI and the askpass helper inside it.
set -eu

cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  # SwiftUI macros and actool ship with Xcode, not the Command Line Tools.
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

version="$(cat ../../VERSION 2>/dev/null || echo 0.0.0)"
# CFBundleShortVersionString allows only numbers and dots.
version="${version%%-*}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# The CLI comes from the release build script; set TINYTOUCH_CLI_BUNDLE to reuse a build.
cli="${TINYTOUCH_CLI_BUNDLE:-../../build/distribution/bin/tinytouch}"
if [ ! -x "$cli/tinytouch" ]; then
  zsh ../../release/build-standalone-macos.sh
fi

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=dist/tinyTouch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$bin/TinyTouchApp" "$app/Contents/MacOS/TinyTouchApp"
cp "$bin/TinyTouchAskpass" "$app/Contents/Helpers/tinytouch-askpass"
ditto "$cli" "$app/Contents/Resources/tinytouch"
xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 27.0 --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp)" >/dev/null
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"

# A team identity keeps the menu bar permission and Keychain access valid wherever
# the app is installed; macOS tracks ad-hoc signed apps by path.
identity="${SIGN_IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null |
  awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"
codesign --force --sign "${identity:--}" --options runtime --timestamp=none \
  "$app/Contents/Helpers/tinytouch-askpass"
# The CLI keeps its own signature and identifier so Keychain keeps trusting it.
codesign --force --sign "${identity:--}" --options runtime --timestamp=none "$app"
codesign --verify --strict "$app"
echo "Signed with: ${identity:-ad-hoc}"

echo "Built $(pwd)/$app"
