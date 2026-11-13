# Developing tinyTouch for macOS

See [building.md](building.md) for requirements and the release build.

## Tests

```sh
swift test    # parser, process runner and store tests
```

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

## Screenshots

The README screenshots in `docs/images/` come from demo mode, so they show sample
data only. Each one has a `-light` and a `-dark` version, at 860 × 600 points with
the window shadow, and uses the default blue accent color. To force an appearance
and accent for the demo app without changing system settings, pass AppKit defaults
after the demo arguments:

```sh
./demo.sh unsaved --tab lighting -AppleInterfaceStyle Dark -AppleAccentColor 4
./demo.sh unsaved --tab lighting -NSRequiresAquaSystemAppearance YES -AppleAccentColor 4
```

The Computers tab shows this Mac's real name, so leave it out of published
screenshots.
