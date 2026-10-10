# tinyTouch for macOS

A menu bar app for configuring tinyTouch. It runs the installed `tinytouch` CLI
for every device operation, so the CLI must be installed first:

```sh
curl -fsSL https://github.com/ZimengXiong/tinyTouch/releases/latest/download/install.sh | sh
```

## Build

Requires Xcode 27 (the SwiftUI macros are not part of the Command Line Tools).

```sh
./build-app.sh                         # builds dist/tinyTouch.app
cp -R dist/tinyTouch.app /Applications/
swift test                             # parser tests
```

`build-app.sh` uses `/Applications/Xcode.app` when `DEVELOPER_DIR` is unset. It signs
with your first Developer ID or Apple Development identity (override with
`SIGN_IDENTITY`), or ad-hoc when none exists. macOS remembers menu bar permission
for ad-hoc signed apps by path, so an ad-hoc copy moved to `/Applications` can
start with a hidden menu bar icon.

## Usage

- The menu bar icon shows connection state, mode, enrolled fingers and helper status.
- **Settings** has tabs for General, Lighting, Fingerprints, Computers and Maintenance.
- Device changes are staged and saved with **Apply**. Each saved change asks for a
  touch from an enrolled finger, just like the CLI.
- Setup, password changes and updates open in Terminal because they read
  passwords or replace the CLI itself.
- Opening the app again from Finder or Spotlight shows Settings. Pass
  `--settings --tab fingers` to open a specific tab at launch.

The app never opens the serial port itself. The CLI coordinates port access with
the HID helper, and the app only polls `tinytouch ports`, which does not open the
device, to notice plug and unplug.
