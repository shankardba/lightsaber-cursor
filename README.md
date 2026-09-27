# Lightsaber Cursor

A personal macOS menu bar app that turns the mouse pointer into a lightsaber.

- The blade points up-left like a normal arrow, and the click point is the blade tip.
- The blade retracts after N idle seconds and re-ignites when the mouse moves.
- Clicking throws a spark, and fast swings leave a motion trail.
- At window edges and dividers the saber steps aside and macOS's own resize arrows appear, so you can see when you're in range to resize. There's an on/off toggle for this.
- The customizer covers 15 hilt styles, 6 finishes, accent and blade colors, blade style (standard / unstable / flat, pointed Darksaber), shimmer, core brightness, length, thickness, and glow.
- 40 character presets (Jedi, Sith, Grey), and you can save your own to "My Sabers".
- The randomizer can change the hilt, the color and the side (Any / Jedi / Sith). It can also pick a new random saber every time the blade re-ignites.
- Auto-switch: an after-dark saber (following macOS Dark Mode or set hours) and per-app sabers. Priority is per-app, then after dark, then your chosen saber.
- Optional sounds, off by default: ignite/retract, clash on click, swing whoosh and a motion hum. The hum's pitch and volume follow cursor speed, and swings are pitched by how fast they are. Each sound has its own toggle and there's a volume slider.
- Toggle it from the menu bar or with ⌃⌥⌘L. Launch at login is optional.

All saber art is drawn in code, so nothing is copied from cursor sites.

## Build & run

Requires only the Xcode Command Line Tools; SwiftPM is not used.

```bash
./scripts/build.sh
open ~/Applications/"Lightsaber Cursor.app"
```

On macOS 26, enable the app under **System Settings → Menu Bar → Allow in the Menu Bar**, or its icon stays hidden.

`build.sh` signs with a self-signed "Lightsaber Cursor Local Signing" certificate from the login keychain when it exists. The app's identity then stays stable, so macOS keeps treating rebuilds as the same app. Without the certificate it falls back to ad-hoc signing.

To review the artwork without launching the app, render a contact sheet of every preset, hilt and state:

```bash
./scripts/build.sh --binary-only && ~/Library/Caches/lightsaber-cursor-build/LightsaberCursor --render-sheet /tmp/sheet.png
```

## How it works

macOS has no public API for replacing the system cursor, and Mousecape-style patching breaks on modern macOS. Instead, the app:

1. Hides the real pointer. It uses the `SetsCursorInBackground` WindowServer property so this works while other apps are frontmost.
2. Draws the saber in click-through, cursor-level overlay windows on every screen, tracking the mouse at 120 Hz.
3. Shows the real pointer while it's over secure system dialogs (password and keychain prompts), which nothing can draw on top of.
4. Shows the real pointer while macOS wants a resize cursor. The app checks `NSCursor.currentSystem` and recognizes resize pointers by their size and centred hotspot. For troubleshooting, `defaults write com.shankar.lightsabercursor debugCursorShapes -bool YES` logs each pointer shape.

Quitting the app, or the app crashing, restores the normal pointer automatically.

## Sounds

The hum is a recorded loop in `Resources/Sounds/hum.wav`, cut from a downloaded lightsaber hum. Ignite, retract and swing are made by pitch-sweeping that hum. The clash is synthesized.

To use your own recordings, drop any of `hum`, `ignite`, `retract`, `swing` or `clash` (`.wav`, `.aif`, `.m4a`, `.mp3` or `.caf`) into:

```
~/Library/Application Support/Lightsaber Cursor/Sounds/
```

Then restart the app. Any file found there replaces the built-in version of that sound. To check what the app will play, export every sound with `LightsaberCursor --export-sounds <dir>`.
