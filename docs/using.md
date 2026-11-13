# Using tinyTouch for macOS

## First launch

On first launch the app walks through connecting tinyTouch, choosing password entry
or smart card mode, and enrolling a finger. It runs `tinytouch --app setup`, which
reads the Mac password from stdin and reports progress as `@tinytouch {json}` lines.

Setup and Change Password check the password against the macOS account and ask
before saving one that doesn't match.

## The main window

The main window opens on **Overview**: the sensor drawn with its ring in the saved
idle color, anything that needs attention, and the latest activity. The sidebar also
has Fingerprints, Lighting, Sign-In, Computers, Activity and Maintenance for the
device (⌘1 to ⌘7).

## Saving changes

- Device changes are staged and saved from the floating **Apply** bar. One touch
  saves every staged setting, because the CLI writes them in one session; a change
  of lighting mode is saved on its own and asks for a second touch. Lighting themes
  are staged like any other edit.
- The touch prompt stays up for the whole command and ends on "Approved". The CLI
  prints nothing when a touch is accepted, so that confirmation comes from the
  command exiting cleanly.

## Names

Fingers and registered computers can be named. The device stores no names, so they
are kept in this Mac's preferences. A finger's name is kept per slot and is dropped
once the device reports that slot empty; it is not tied to one tinyTouch.

## Application settings

- **Application** (⌘,) controls the menu bar icon, opening at login, notifications,
  and installing the `tinytouch` command into `~/.local/bin`. The command is a link to
  the CLI inside the app, so it stays current when you update the app.
- **Menu Bar** chooses what the menu bar item shows and which shortcuts it offers.
- **Updates**, in Application settings, turns the daily check for a new version on
  or off, and whether a new version downloads in the background and installs when
  tinyTouch quits. **Check Now** looks right away.
- **About** shows versions, authors and links, and has **Check for Updates…**.
- With the menu bar icon off, the app shows a Dock icon and quits when its window
  closes. Password entry keeps working, because the background helper runs on its own.

## Updates

The app updates itself with [Sparkle](https://sparkle-project.org). It reads the
feed attached to the latest GitHub release,
`releases/latest/download/appcast.xml`. The feed and each disk image are signed
with the project's EdDSA key, and the app refuses an unsigned feed or an update
that fails the check (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`). The
new app must also carry the same Developer ID signature.

After an update, the running helper still has the replaced CLI loaded. On the first
launch of a new build, the app reinstalls the helper from its own CLI with
`tinytouch --app _upgrade-helper`, which checks that Keychain still trusts it
first. Debug and demo builds never update themselves.

## The background helper

If the helper was installed by a standalone CLI, the app moves it onto its bundled
CLI at launch when Keychain already trusts that signature, and otherwise asks for
the login Keychain password.

The app never opens the serial port itself. The CLI coordinates port access with
the HID helper, and the app watches IOKit for serial devices to notice plug and
unplug.
