# tinyTouch for macOS

The tinyTouch app: first-run setup, device settings, and a menu bar status item.
It carries its own signed copy of the `tinytouch` CLI and runs it for every device
operation, so nothing else needs to be installed and nothing opens Terminal.

## Build

Requires Xcode 27 (the SwiftUI macros and `actool` are not part of the Command Line
Tools) and a Python 3.13 with bundled Expat, such as one managed by `uv`, for the CLI.

```sh
TINYTOUCH_PYTHON="$(uv python find --managed-python 3.13)" ./build-app.sh
cp -R dist/tinyTouch.app /Applications/
swift test                             # parser tests
```

`build-app.sh` builds the CLI with `release/build-standalone-macos.sh` unless
`build/distribution/bin/tinytouch` already exists (or `TINYTOUCH_CLI_BUNDLE` points
at one), compiles `Resources/AppIcon.icon` with `actool`, and signs with your first
Developer ID or Apple Development identity (override with `SIGN_IDENTITY`).

Use the same identity for every build. Keychain grants the background helper access
by the CLI's signature, so a different identity makes the helper ask for Keychain
authorization again.

## Layout

- `Contents/MacOS/TinyTouchApp` is the app.
- `Contents/Resources/tinytouch/` is the PyInstaller CLI, signed as `com.tinytouch.cli`.
  The HID helper's launch agent runs it from here.
- `Contents/Helpers/tinytouch-askpass` shows the administrator password prompt that
  `sudo` needs when the CLI pairs a smart card identity.

## Usage

- On first launch the app walks through connecting tinyTouch, choosing password
  entry or smart card mode, and enrolling a finger. It runs
  `tinytouch --app setup`, which reads the Mac password from stdin and reports
  progress as `@tinytouch {json}` lines.
- The main window's sidebar has General, Lighting, Fingerprints, Computers, Activity
  and Maintenance for the device. Device changes are staged and saved with **Apply**;
  each saved change asks for a touch from an enrolled finger, just like the CLI.
- **Application** (⌘,) controls the menu bar icon, opening at login, notifications, and
  installing the `tinytouch` command into `~/.local/bin`. **About** shows versions,
  authors and links.
- With the menu bar icon off, the app shows a Dock icon and quits when its window
  closes. Password entry keeps working, because the background helper runs on its own.
- If the helper was installed by a standalone CLI, the app moves it onto its bundled
  CLI at launch when Keychain already trusts that signature, and otherwise asks for
  the login Keychain password.

The app never opens the serial port itself. The CLI coordinates port access with
the HID helper, and the app watches IOKit for serial devices to notice plug and unplug.
