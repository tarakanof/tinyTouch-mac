# Building tinyTouch for macOS

Most people should download the notarized disk image from the
[latest release](https://github.com/tarakanof/tinyTouch-mac/releases/latest).
Build from source to change the app, or to make a release.

## Requirements

- macOS 27.
- Xcode 27. The SwiftUI macros and `actool` are not part of the Command Line Tools.
- A Python 3.13 with bundled Expat, such as one managed by `uv`, for the CLI.

## Build and install

```sh
git clone --recurse-submodules https://github.com/tarakanof/tinyTouch-mac.git
cd tinyTouch-mac
TINYTOUCH_PYTHON="$(uv python find --managed-python 3.13)" ./build-app.sh
cp -R dist/tinyTouch.app /Applications/
swift test                             # parser, process runner and store tests
```

If you cloned without `--recurse-submodules`, run `git submodule update --init` first.

`build-app.sh` builds the CLI from the `tinytouch` submodule unless
`build/cli/bin/tinytouch` already exists (or `TINYTOUCH_CLI_BUNDLE` points at one),
compiles `Resources/AppIcon.icon` with `actool`, and signs with your first
Developer ID or Apple Development identity (override with `SIGN_IDENTITY`).

To update an installed copy, quit tinyTouch, replace `/Applications/tinyTouch.app`
with the new build, and open it again. The background helper restarts on its own.

## Signing

Use the same identity for every build. Keychain grants the background helper access
by the CLI's signature, so a different identity makes the helper ask for Keychain
authorization again.

## Making a release

`release.sh` builds `dist/tinyTouch-<version>.dmg`, signed with Developer ID and
notarized, its SHA-256 checksum, and `dist/appcast.xml`, the Sparkle feed that
installed copies check for updates. It needs:

- a clean working tree and a Developer ID Application identity;
- release notes in `docs/releases/<version>.md`, in Markdown. They appear in the
  app's update window and on the GitHub release;
- a `notarytool` keychain profile. Create it once, in Terminal, with an
  app-specific password from account.apple.com:

  ```sh
  xcrun notarytool store-credentials tinytouch-notary --apple-id <apple-id> --team-id <team-id>
  ```

- the Sparkle signing key in the login Keychain, under the account
  `tinytouch-mac`. Its public half is `SUPublicEDKey` in `Resources/Info.plist`.

Then:

1. Set the version in `VERSION`, write `docs/releases/<version>.md`, and merge both.
2. Run `./release.sh` on `main` (`NOTARY_PROFILE=<name>` picks another profile). It
   builds with `RELEASE=1`, notarizes and staples the app, packs it into a disk
   image with a link to Applications, notarizes and staples the disk image, then
   signs it for Sparkle and writes the signed feed with `make-appcast.sh`. Each
   notarization usually takes a few minutes.
3. Publish it. The feed must be attached, or installed copies won't see the update:

   ```sh
   v=$(cat VERSION)
   gh release create "v$v" "dist/tinyTouch-$v.dmg" "dist/tinyTouch-$v.dmg.sha256" \
     dist/appcast.xml --title "tinyTouch $v" --notes-file "docs/releases/$v.md"
   ```

Sparkle offers an update when the feed's build number (`CFBundleVersion`, the
commit count of the built commit) is higher than the installed one, so build
releases from `main`.

### The Sparkle signing key

Only this key can sign updates that installed copies accept. Back it up once and
keep the copy somewhere safe, such as a password manager:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account tinytouch-mac -x sparkle-key.txt
```

Move the file into the password manager and delete it. To set up another Mac,
import it with `generate_keys --account tinytouch-mac -f sparkle-key.txt`. If the
key is lost, installed copies can't verify new updates: people would have to
download a new version by hand once.

`RELEASE=1 ./build-app.sh` is what makes the bundle notarizable: it signs the CLI
and its Python libraries with the hardened runtime and a secure timestamp. The CLI
keeps the designated requirement its own signing script pins (`com.tinytouch.cli`
and the team), so Keychain keeps trusting the helper after an update.

When the app runs from the disk image, or from a copy macOS translocated, it offers
to move itself to `/Applications` before doing anything else, because setup
records the CLI's path in the helper's launch agent.

## The CLI submodule

The app needs a few CLI and helper changes that upstream does not have yet: an app
mode that takes secrets from stdin and reports setup events, saving several settings
with one approval, and marking this Mac in the computers list. The `tinytouch`
submodule therefore pins the `app-cli` branch of
[tarakanof/tinyTouch-fork](https://github.com/tarakanof/tinyTouch-fork), which is
upstream plus those changes. Once upstream has them, the submodule will point at
upstream.

The app's version is in `VERSION`. The CLI and firmware keep their own versions.

## Bundle layout

- `Contents/MacOS/TinyTouchApp` is the app.
- `Contents/Resources/tinytouch/` is the PyInstaller CLI, signed as `com.tinytouch.cli`.
  The HID helper's launch agent runs it from here.
- `Contents/Helpers/tinytouch-askpass` shows the administrator password prompt that
  `sudo` needs when the CLI pairs a smart card identity.
