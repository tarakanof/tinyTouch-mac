#!/bin/sh
# Writes dist/appcast.xml, the Sparkle feed for one release, and signs it.
#   ./make-appcast.sh <disk image> <app> <release notes .md>
# DOWNLOAD_URL overrides the disk image's URL (default: the GitHub release asset).
# The private EdDSA key is read from the login Keychain (account tinytouch-mac).
set -eu

cd "$(dirname "$0")"
dmg="$1"; app="$2"; notes="$3"
tools=.build/artifacts/sparkle/Sparkle/bin
account="${SPARKLE_KEY_ACCOUNT:-tinytouch-mac}"
[ -x "$tools/sign_update" ] || swift package resolve >/dev/null

info="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$info")"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$info")"
minimum="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$info")"
repo=https://github.com/tarakanof/tinyTouch-mac
url="${DOWNLOAD_URL:-$repo/releases/download/v$version/$(basename "$dmg")}"
# Prints: sparkle:edSignature="…" length="…"
enclosure="$("$tools/sign_update" --account "$account" "$dmg")"

feed=dist/appcast.xml
{
  cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>tinyTouch</title>
    <link>$repo</link>
    <item>
      <title>tinyTouch $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$repo/releases/tag/v$version</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[
EOF
  cat "$notes"
  cat <<EOF
]]></description>
      <enclosure url="$url" $enclosure type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
} > "$feed"
xmllint --noout "$feed"
# Embeds the feed's own signature; the app requires it (SURequireSignedFeed).
"$tools/sign_update" --account "$account" --disable-signing-warning "$feed" >/dev/null
"$tools/sign_update" --account "$account" --verify "$feed" >/dev/null
echo "Wrote $feed for $version ($build)"
