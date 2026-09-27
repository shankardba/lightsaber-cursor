# Lightsaber Cursor

A personal macOS menu bar app that turns the mouse pointer into a lightsaber.

- The blade points up-left like a normal arrow, and the click point is the blade tip.
- Hovering anything clickable (buttons, links, menu items, Dock icons) makes the blade flare instead of switching to a hand cursor.
- The blade retracts after N idle seconds and re-ignites when the mouse moves.
- Clicking throws a spark, and fast swings leave a motion trail.
- The customizer covers 14 hilt styles, 6 finishes, accent and blade colors, blade style (standard / unstable / Darksaber), shimmer, core brightness, length, thickness, and glow.
- 40 character presets (Jedi, Sith, Grey), and you can save your own to "My Sabers".
- The randomizer can change the hilt, the color and the side (Any / Jedi / Sith). It can also pick a new random saber every time the blade re-ignites.
- Auto-switch: an after-dark saber (following macOS Dark Mode or set hours) and per-app sabers. Priority is per-app, then after dark, then your chosen saber.
- Optional synthesized sounds, off by default: ignite/retract, clash on click and swing whoosh, each with its own toggle and a volume slider.
- Toggle it from the menu bar or with ⌃⌥⌘L. Launch at login is optional.

All saber art is drawn in code, so nothing is copied from cursor sites.

## Build & run

Requires only the Xcode Command Line Tools; SwiftPM is not used.

```bash
./scripts/build.sh
open ~/Applications/"Lightsaber Cursor.app"
```

Grant **System Settings → Privacy & Security → Accessibility** access so the app can see what's under the pointer (needed for the hover glow). On macOS 26, also enable the app under **System Settings → Menu Bar → Allow in the Menu Bar**, or its icon stays hidden.

`build.sh` signs with a self-signed "Lightsaber Cursor Local Signing" certificate from the login keychain when it exists. The app's identity then stays stable, so the Accessibility grant survives rebuilds. Without the certificate it falls back to ad-hoc signing, and the permission must be re-granted after every rebuild.

To review the artwork without launching the app, render a contact sheet of every preset, hilt and state:

```bash
./scripts/build.sh --binary-only && ~/Library/Caches/lightsaber-cursor-build/LightsaberCursor --render-sheet /tmp/sheet.png
```

## How it works

macOS has no public API for replacing the system cursor, and Mousecape-style patching breaks on modern macOS. Instead, the app:

1. Hides the real pointer. It uses the `SetsCursorInBackground` WindowServer property so this works while other apps are frontmost.
2. Draws the saber in click-through, cursor-level overlay windows on every screen, tracking the mouse at 120 Hz.
3. Asks the Accessibility API what element is under the pointer (`AXUIElementCopyElementAtPosition`) and flares the blade when it's clickable.

Quitting the app, or the app crashing, restores the normal pointer automatically.
