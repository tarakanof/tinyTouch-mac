#!/bin/sh
# Builds a notarized dist/tinyTouch-<version>.dmg and the Sparkle feed dist/appcast.xml,
# ready to attach to a GitHub release. Release notes come from docs/releases/<version>.md.
#   NOTARY_PROFILE=tinytouch-notary ./release.sh
# The profile is a notarytool keychain profile; create it once with
#   xcrun notarytool store-credentials tinytouch-notary --apple-id <id> --team-id <team>
set -eu

cd "$(dirname "$0")"
profile="${NOTARY_PROFILE:-tinytouch-notary}"
version="$(cat VERSION)"
dmg="dist/tinyTouch-$version.dmg"
notes="docs/releases/$version.md"

if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
  echo "The working tree has uncommitted changes. Commit them or set ALLOW_DIRTY=1." >&2
  exit 1
fi
if [ ! -s "$notes" ]; then
  echo "Write the release notes in $notes first." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "No working notarytool profile '$profile'. Create it with:" >&2
  echo "  xcrun notarytool store-credentials $profile --apple-id <apple-id> --team-id <team-id>" >&2
  exit 1
fi

RELEASE=1 ./build-app.sh
app=dist/tinyTouch.app
identity="$(codesign -d --verbose=2 "$app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p')"

notarize() {
  echo "Notarizing $(basename "$1")…"
  xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --timeout 30m \
    --output-format json > dist/notary.json
  status="$(jq -r .status dist/notary.json)"
  if [ "$status" != Accepted ]; then
    echo "Notarization ended with status '$status':" >&2
    xcrun notarytool log "$(jq -r .id dist/notary.json)" --keychain-profile "$profile" >&2 || true
    exit 1
  fi
}

# Staple the app itself, so it opens offline once copied out of the disk image.
ditto -c -k --keepParent "$app" dist/tinyTouch-notarize.zip
notarize dist/tinyTouch-notarize.zip
rm dist/tinyTouch-notarize.zip
xcrun stapler staple "$app"

# A disk image with the app and a link to Applications, to drag one onto the other.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/tinyTouch.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname tinyTouch -srcfolder "$staging" -fs APFS -format ULMO "$dmg"
codesign --force --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
rm -f dist/notary.json

xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
spctl --assess --type execute --verbose=2 "$app"
(cd dist && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
# Signed after stapling, which changes the disk image.
./make-appcast.sh "$dmg" "$app" "$notes"
echo "Built $(pwd)/$dmg"
cat "$dmg.sha256"
