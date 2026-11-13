# tinyTouch for macOS

A SwiftUI menu bar app that drives tinyTouch through the `tinytouch` CLI bundled from the
`tinytouch/` submodule. [README](README.md) says what it does; [docs/](docs/) holds the
details.

- Build and test with Xcode's toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
  The Command Line Tools lack the SwiftUI macros, so SourceKit's macro errors are noise.
- The CLI owns the serial port, the HID helper and Keychain. Device commands go through
  `CLI.run`, which queues them; secrets reach the CLI on stdin.
- The helper's Keychain access depends on the CLI's signature: identifier
  `com.tinytouch.cli`, the pinned requirement in `build-app.sh`, one signing team.
- Look at the interface with `./demo.sh` (sample data, never touches the device); see
  [docs/development.md](docs/development.md). Releases and updates: [docs/building.md](docs/building.md).
- The review step for every PR is the `pr-review` skill; its profile is
  `docs/agents/pr-review.md`.
