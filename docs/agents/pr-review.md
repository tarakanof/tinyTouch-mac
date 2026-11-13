# PR review profile

## Product

A macOS 27 menu bar app for tinyTouch, a USB fingerprint key: when a person touches it,
the background helper types their Mac password or the key acts as a smart card. The app
runs a bundled, signed copy of the `tinytouch` CLI (submodule `tinytouch/`) for every
device operation; the CLI owns the serial port, the HID helper and Keychain. The person
is a Mac user who set up tinyTouch once and expects touch sign-in to keep working across
app updates. The wrong action on their behalf: password entry silently stops, their
password leaks, an unsigned or wrong update installs, or a command reaches the device
they didn't ask for.

## Severity

- **blocker**: password entry breaks after a normal flow (setup, update, move, repair):
  the helper left on a replaced or missing CLI, or its launch agent pointing at a path
  that goes away; the CLI's identifier (`com.tinytouch.cli`) or designated requirement
  changes, or builds switch signing team, so Keychain stops trusting the helper; the Mac
  password reaches argv, logs, crash output or UI instead of the CLI's stdin; two
  device commands run at once, or the app opens the serial port itself; a release that
  fails notarization or Gatekeeper; an update channel that accepts an unsigned feed or
  update, or rejects the next real one (`SUPublicEDKey`, `SURequireSignedFeed`, a
  build number that doesn't increase, no `appcast.xml` on the release).
- **should-fix**: a touch prompt, busy spinner or setup phase that sticks after cancel,
  error or reconnect; a runtime dependency missing from the app or demo bundle; a toolbar
  item whose width changes; a mirror of external state that goes stale; DeviceStore logic
  that the fake CLI could test but no test covers; a test that passes without reaching
  the path it names; personal data (computer names, ports, finger names) in screenshots
  or docs.
- **nit**: doc wording, naming, comment style.

## Do not flag

- SourceKit diagnostics such as "plugin for module 'SwiftUIMacros' not found" or "Cannot
  find X in scope": the editor's index; `swift build` is the judge.
- Code inside the `tinytouch/` submodule (upstream fork). Flag only the pointer change
  and how the app calls the CLI. Known CLI residual: `current_port()` falls back to the
  first serial port when the saved one vanishes, which can be another USB device.
- `Package.resolved`, `docs/images/*`, and the demo data in `DeviceStore`'s DEBUG
  extension.
- The `unsafeFlags` rpath in `Package.swift`: deliberate, and fine for a root package.
- `UserDefaults.standard` in `AppPreferences`: deliberate. Tests that write defaults go
  through an injected store instead (`DeviceStore(defaults:)`).
- The hard-coded `tarakanof/tinyTouch-mac` URLs in the feed, docs and scripts.
- Missing CI: there is none yet (hosted runners lack macOS 27 / Xcode 27).

## Defect classes

- **Command ownership** (`DeviceStore`: `setupRun`, `approvalTask`, `enrollmentRun`,
  `touchPrompt`, `setupPhase`): an async CLI result writes shared state only while its
  run still owns it (`setupRun == run`). Lifecycle: start, cancel (`resetSetup`,
  `cancelApproval`, enrollment cancel), error, reconnect, a newer run superseding it.
  Find sites: `grep -n 'setupRun\|approvalTask\|enrollmentRun\|touchPrompt =' DeviceStore.swift`.
- **Busy accounting** (`perform`, `busyCount`, `portChangePending`): every device command
  runs inside `perform`, so the count balances on throw and cancel, and a port change
  seen while busy is replayed once idle.
- **Serial exclusivity** (`CLI.run` vs `CLI.runDetached`): anything that opens the port
  uses the queued `run`; `runDetached` only for commands that never touch the device
  (`ports`, `--version`).
- **Helper binding** (`migrateHelperIfNeeded`, `helperBuild`, `installHelper`,
  `runSetup`, `AppLocation`, the launch agent's `ProgramArguments`): any change to the
  app's path, build or bundled CLI leaves the helper on this app's CLI. Record the build
  only after the CLI succeeded; never run setup from a disk image or translocated copy.
- **Keychain identity** (`build-app.sh`, `tinytouch/release/sign-macos-cli.sh`): the CLI
  keeps identifier `com.tinytouch.cli` and the requirement `identifier … and anchor apple
  generic and certificate leaf[subject.OU] = <team>`; every build uses one team.
- **Release and update chain** (`build-app.sh` with `RELEASE=1`, `release.sh`,
  `make-appcast.sh`, `Resources/Info.plist` `SU*` keys): every Mach-O, including new
  frameworks and their helpers, gets the hardened runtime and a secure timestamp, signed
  inside out; notarize after signing; `sign_update` after stapling; `CFBundleVersion`
  (commit count) increases; the release carries the disk image, checksum and appcast.
- **Bundle completeness** (`build-app.sh`, `demo.sh`): whatever the binary links or loads
  at runtime is copied into both the app and the demo bundle (PR #4: Sparkle missing
  from the demo crashed it at launch).
- **Toolbar measurement** (`MainView` toolbar items): an item keeps a constant width;
  swap content in place. NSToolbar doesn't re-fit an item that grows, and pushes it into
  the overflow menu (PR #1).
- **State mirrors** (`Updater`, `AppPreferences.refresh`): a mirror of state another
  component can change observes it (KVO, refresh on activation) and writes back only
  when the value differs.
- **Test reaches its path** (`Tests/`): a failure-path test first gets past the earlier
  guards (connect with `refreshAll`), makes the step under test fail through the fake
  CLI, and asserts the failure came from that step (PR #4 round 2).

## Self-check

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test                     # the full suite takes seconds
swift build -c release         # Updater's real path compiles only in release
./demo.sh main                 # when the bundle, a dependency or a view changes: it must open (quit with ⌘Q)
RELEASE=1 ./build-app.sh && codesign --verify --deep --strict dist/tinyTouch.app   # when signing, packaging or Info.plist changes
```

## Checks before a re-check

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Also run `swift build -c release` when a fix touches `Updater` or other non-DEBUG code.

## Settings

- rounds: 3
- reviewer_model: opus
- reviewer_effort: medium
- lite_model: sonnet
- lite_effort: low
- lite_max_lines: 40
- sensitive_paths: *auth*, *login*, *secret*, *credential*, *keychain*, *crypto*, *token*, *migration*, *.sql, .github/workflows/*, build-app.sh, release.sh, make-appcast.sh, Package.swift, Resources/Info.plist, tinytouch, Sources/TinyTouchApp/CLI.swift, Sources/TinyTouchApp/DeviceStore.swift, Sources/TinyTouchApp/AppLocation.swift, Sources/TinyTouchApp/Updater.swift, Sources/TinyTouchAskpass/*
- codex: auto
