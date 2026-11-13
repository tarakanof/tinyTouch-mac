#!/bin/sh
# Opens a debug build filled with sample data instead of a device, to look at the
# interface. It never runs the tinytouch CLI, so it is safe next to an installed
# tinyTouch.   ./demo.sh [scene] [--tab NAME]
set -eu

cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  # SwiftUI macros ship with Xcode, not the Command Line Tools.
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build
# Notifications need an app bundle. Its own identifier keeps the demo's
# preferences apart from the real app's.
app=.build/tinyTouch-demo.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build --show-bin-path)/TinyTouchApp" "$app/Contents/MacOS/TinyTouchApp"
sed -e 's/__VERSION__/0.0.0/' -e 's/__BUILD__/1/' \
  -e 's/dev.tinytouch.settings/dev.tinytouch.settings.demo/' \
  Resources/Info.plist > "$app/Contents/Info.plist"

scene="${1:-main}"
if [ $# -gt 0 ]; then shift; fi
exec "$app/Contents/MacOS/TinyTouchApp" --demo "$scene" --settings "$@"
