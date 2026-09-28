# Lightsaber Cursor (macOS)

A personal macOS menu bar app that turns the mouse pointer into a lightsaber, or a golden sword. The Windows version lives in a separate repo, [`shankardba/lightsaber-cursor-windows`](https://github.com/shankardba/lightsaber-cursor-windows).

- The blade points up-left like a normal arrow, and the click point is the blade tip.
- The blade retracts after N idle seconds and re-ignites when the mouse moves.
- Clicking throws a spark, and fast swings leave a motion trail.
- At window edges and dividers the saber steps aside so macOS's own resize arrows show.
- The customizer covers 17 hilt styles, 6 finishes, accent and blade colors, blade style (standard / unstable / Darksaber / Metal Sword / Plasma Sword), shimmer, core brightness, length, thickness and glow.
- 45 character presets (Jedi, Sith, Grey), and you can save your own to "My Sabers".
- The randomizer can change the hilt, the color and the side (Any / Jedi / Sith). It can also pick a new random saber every time the blade re-ignites.
- Auto-switch: an after-dark saber (following Dark Mode or set hours) and per-app sabers.
- Optional sounds (off by default).
- Toggle it from the menu bar or with **⌃⌥⌘L** (Control-Option-Command-L).

All saber art is drawn in code.

---

## Setup, step by step

### What you need

- A Mac running **macOS 14 (Sonoma) or newer**, on Apple silicon (M1 or later).
- About 5 minutes.
- No Apple developer account, no Xcode app and no special permissions (Accessibility, Screen Recording and so on).

### Step 1: Install Apple's Command Line Tools

Open **Terminal** (Applications → Utilities → Terminal) and run:

```bash
xcode-select --install
```

Click **Install** in the dialog and wait for it to finish. If it says the tools are already installed, move on.

### Step 2: Get the code

Pick one of these:

- **If the project already syncs to this Mac through iCloud Drive,** it's in `iCloud Drive/Projects/lightsaber-cursor`. Go to it in Terminal:
  ```bash
  cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/Projects/lightsaber-cursor
  ```
- **Otherwise, clone it from GitHub.** This asks you to sign in to GitHub, because the repo is private.
  ```bash
  git clone https://github.com/shankardba/lightsaber-cursor.git
  cd lightsaber-cursor
  ```

### Step 3: Build and install

In that same Terminal window, run:

```bash
./scripts/build.sh
```

This compiles the app and installs it as **`~/Applications/Lightsaber Cursor.app`**, the Applications folder inside your home folder. It takes about a minute.

> If a dialog says **"codesign wants to access key…"**, type your Mac login password and click **Always Allow**. It only appears on a Mac where you've set up the optional signing certificate (see *Optional: stable signing* below).

### Step 4: Launch it

```bash
open ~/Applications/"Lightsaber Cursor.app"
```

You can also open it from Spotlight: press ⌘-Space and type *Lightsaber*. On first launch the **Customizer** window opens, and your pointer becomes a lightsaber (Obi-Wan's by default).

### Step 5: Show the menu bar icon (macOS 26 and later)

macOS 26 hides new menu bar icons until you allow them:

1. Open **System Settings → Menu Bar**.
2. Scroll to **Allow in the Menu Bar**.
3. Turn on **Lightsaber Cursor**.

The saber icon appears near the right end of the menu bar. On MacBooks with a camera notch, icons can hide under the notch when the menu bar is full. The app places itself to the right of the notch. If you still can't see it, hold **⌘** and drag the menu bar icons around, or turn off icons you don't need.

### Step 6: Pick your saber

1. Click the saber icon in the menu bar and choose **Customize…**. Opening the app from Spotlight again also works.
2. On the **Saber** tab, pick a preset on the left (for example *Agamemnon (Golden Sword)* or *Sabine Wren (Darksaber)*), or build your own with the controls on the right. Changes apply to your pointer immediately.
3. Click **Save New** to keep a custom saber under *My Sabers*.

### Step 7: Launch at login (optional)

Customizer → **Behavior** tab → **System** → turn on **Launch at login**.

### Everyday use

| To… | Do this |
|---|---|
| Turn the saber on or off | Press **⌃⌥⌘L**, or menu bar icon → **Lightsaber Cursor** |
| Switch sabers quickly | Menu bar icon → **Sabers** |
| Get a random saber | Menu bar icon → **Randomize** |
| Turn effects on or off | Menu bar icon → Retract When Idle / Click Spark / Motion Trail / Resize Arrows / Sounds |
| Change settings | Menu bar icon → **Customize…** |
| Quit (normal pointer comes back) | Menu bar icon → **Quit Lightsaber Cursor** |

### Troubleshooting

- **No menu bar icon:** see Step 5 (Allow in the Menu Bar, and the notch). While the icon is hidden, ⌃⌥⌘L still toggles the saber, and opening the app from Spotlight shows the Customizer.
- **The saber disappears over password or keychain prompts:** this is expected. macOS doesn't let any app draw over secure dialogs, so the normal pointer shows there.
- **The pointer is stuck invisible:** this shouldn't happen, because quitting or a crash restores it. If it ever does, run `killall LightsaberCursor` in Terminal and the normal pointer returns.
- **"App can't be opened" after copying the `.app` to another Mac:** macOS blocks apps not signed by Apple the first time. Open **System Settings → Privacy & Security** and click **Open Anyway**. Building on that Mac with Step 3 avoids this.

### Uninstall

1. Menu bar icon → **Quit Lightsaber Cursor**.
2. Turn off **Launch at login** first if you'd enabled it.
3. Delete `~/Applications/Lightsaber Cursor.app`.
4. To remove saved settings too, run:
   ```bash
   defaults delete com.shankar.lightsabercursor
   ```

### Optional: stable signing

`build.sh` signs the app with a self-signed certificate named **"Lightsaber Cursor Local Signing"** if your login keychain has one. Otherwise it uses ad-hoc signing, which is fine because the app needs no special permissions. The certificate only keeps the app's identity identical across rebuilds. To create it on a new Mac:

```bash
cd "$(mktemp -d)"
printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Lightsaber Cursor Local Signing\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > cs.cnf
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cs.cnf
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "Lightsaber Cursor Local Signing" -out cs.p12 -passout pass:temp
security import cs.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm key.pem cs.p12
```

On the first build afterwards, answer the keychain prompt with your password and **Always Allow**.

---

## Developer notes

To review the artwork without launching the app:

```bash
./scripts/build.sh --binary-only
~/Library/Caches/lightsaber-cursor-build/LightsaberCursor --render-sheet /tmp/sheet.png
~/Library/Caches/lightsaber-cursor-build/LightsaberCursor --render-preset "Agamemnon (Golden Sword)" /tmp/sword.png
```

### How it works

macOS has no public API for replacing the system cursor, and Mousecape-style patching breaks on modern macOS. Instead, the app:

1. Hides the real pointer. It uses the `SetsCursorInBackground` WindowServer property so this works while other apps are frontmost.
2. Draws the saber in click-through, maximum-level overlay windows on every screen, tracking the mouse at 120 Hz.
3. Shows the real pointer over secure system dialogs (password and keychain prompts), which nothing can draw on top of.
4. Shows the real pointer while macOS wants a resize cursor. The app checks `NSCursor.currentSystem` and recognizes resize pointers by their size and centred hotspot. For troubleshooting, `defaults write com.shankar.lightsabercursor debugCursorShapes -bool YES` logs each pointer shape.

Quitting the app, or the app crashing, restores the normal pointer automatically.

### Sounds

The hum is a recorded loop in `Resources/Sounds/hum.wav`. Ignite, retract and swing are made by pitch-sweeping that hum, and the clash is synthesized. To use your own recordings, drop any of `hum`, `ignite`, `retract`, `swing` or `clash` (`.wav`, `.aif`, `.m4a`, `.mp3` or `.caf`) into `~/Library/Application Support/Lightsaber Cursor/Sounds/` and restart the app. `LightsaberCursor --export-sounds <dir>` exports what the app will play.
