# Building tinyTouch for macOS

There is no prebuilt download yet; build it from source.

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
