#!/bin/sh
# Builds dist/tinyTouch.app with the tinytouch CLI and the askpass helper inside it.
set -eu

cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  # SwiftUI macros and actool ship with Xcode, not the Command Line Tools.
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

version="${APP_VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"
# CFBundleShortVersionString allows only numbers and dots.
version="${version%%-*}"
# Sparkle offers an update when the appcast's build number is higher than this.
build="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# The CLI is built from the tinytouch submodule; set TINYTOUCH_CLI_BUNDLE to reuse a build.
cli="${TINYTOUCH_CLI_BUNDLE:-build/cli/bin/tinytouch}"
if [ ! -x "$cli/tinytouch" ]; then
  if [ ! -f tinytouch/release/build-standalone-macos.sh ]; then
    echo "The tinytouch submodule is missing. Run: git submodule update --init" >&2
    exit 1
  fi
  # Keep the CLI's build output in this repository, not inside the submodule.
  TINYTOUCH_BUILD_DIR="$PWD/build/cli" TINYTOUCH_VENV_DIR="$PWD/build/cli-venv" \
    TINYTOUCH_OUTPUT="$PWD/build/cli/tinytouch.tar.gz" \
    zsh tinytouch/release/build-standalone-macos.sh
fi

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=dist/tinyTouch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers" "$app/Contents/Frameworks"
cp "$bin/TinyTouchApp" "$app/Contents/MacOS/TinyTouchApp"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
# Sparkle uses its XPC services only in sandboxed apps; this app isn't sandboxed.
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
  "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
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
timestamp=--timestamp=none
if [ "${RELEASE:-0}" = 1 ]; then
  # Notarization needs a Developer ID signature, a secure timestamp and the
  # hardened runtime on every executable in the bundle.
  case "$identity" in
    "Developer ID Application:"*) ;;
    *) echo "A release needs a Developer ID Application identity, not '${identity:-ad-hoc}'." >&2; exit 1 ;;
  esac
  timestamp=--timestamp
  cli_dir="$app/Contents/Resources/tinytouch"
  find "$cli_dir/_internal" -type f \( -name '*.so' -o -name '*.dylib' \) -print0 |
    xargs -0 codesign --force --sign "$identity" --options runtime --timestamp
  # Keep the requirement the CLI's own signing script pins, so Keychain keeps
  # trusting the helper across builds: product identifier and team, no hash.
  team="$(codesign -d --verbose=2 "$cli_dir/tinytouch" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  requirement="identifier \"com.tinytouch.cli\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\""
  codesign --force --sign "$identity" --identifier com.tinytouch.cli --options runtime --timestamp \
    --requirements "=designated => $requirement" "$cli_dir/tinytouch"
  codesign --verify --strict -R "=$requirement" "$cli_dir/tinytouch"
fi
codesign --force --sign "${identity:--}" --options runtime $timestamp \
  "$app/Contents/Helpers/tinytouch-askpass"
# Sparkle's helpers inside out, then the framework, as Sparkle documents.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "${identity:--}" --options runtime $timestamp "$sparkle/Versions/B/Autoupdate"
codesign --force --sign "${identity:--}" --options runtime $timestamp "$sparkle/Versions/B/Updater.app"
codesign --force --sign "${identity:--}" --options runtime $timestamp "$sparkle"
# The CLI keeps its own signature and identifier so Keychain keeps trusting it.
codesign --force --sign "${identity:--}" --options runtime $timestamp "$app"
codesign --verify --strict "$app"
echo "Signed with: ${identity:-ad-hoc}"

echo "Built $(pwd)/$app"
