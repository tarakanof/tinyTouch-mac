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
swift test                             # parser, process runner and store tests
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
- The main window opens on **Overview**: the sensor drawn with its ring in the saved
  idle color, anything that needs attention, and the latest activity. The sidebar
  also has Fingerprints, Lighting, Sign-In, Computers, Activity and Maintenance for
  the device (⌘1 to ⌘7).
- Device changes are staged and saved from the floating **Apply** bar. One touch
  saves every staged setting, because the CLI writes them in one session; a change
  of lighting mode is saved on its own and asks for a second touch. Lighting themes
  are staged like any other edit.
- The touch prompt stays up for the whole command and ends on "Approved". The CLI
  prints nothing when a touch is accepted, so that confirmation comes from the
  command exiting cleanly.
- Fingers and registered computers can be named. The device stores no names, so
  they are kept in this Mac's preferences. A finger's name is kept per slot and is
  dropped once the device reports that slot empty; it is not tied to one tinyTouch.
- Setup and Change Password check the password against the macOS account and ask
  before saving one that doesn't match.
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

## Looking at the interface without a device

`./demo.sh [scene] [--tab NAME]` opens a debug build filled with sample data. It
never runs the CLI, so it is safe next to an installed tinyTouch, and it keeps its
preferences under its own bundle identifier.

```sh
./demo.sh                         # connected device, Overview
./demo.sh unsaved --tab lighting  # an edit waiting in the Apply bar
./demo.sh prompt --tab sign-in    # the touch prompt
```

Scenes: `main`, `disconnected`, `prompt`, `approved`, `enroll`, `piv`, `setup`,
`unsaved`. Tabs: `overview`, `fingers`, `lighting`, `sign-in`, `computers`,
`activity`, `maintenance`, `app`, `menu`, `about`. Quit with ⌘Q or Ctrl-C.
