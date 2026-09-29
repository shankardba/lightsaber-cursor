#!/bin/zsh
# One-step setup: installs Apple's Command Line Tools if needed, builds and installs the app, and launches it.
# On its first launch the app asks about starting at login, and helps if macOS hides its menu bar icon.
set -euo pipefail
cd "${0:A:h:h}"

step() { print -P "\n%F{cyan}%B==> $*%b%f"; }
note() { print -P "    $*"; }
fail() { print -P "\n%F{red}%B$*%b%f"; osascript -e "display alert \"Lightsaber Cursor setup\" message \"$*\"" >/dev/null 2>&1 || true; exit 1; }

print -P "%BLightsaber Cursor setup%b"

step "Checking macOS"
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "Lightsaber Cursor needs macOS 14 (Sonoma) or newer. This Mac has $(sw_vers -productVersion)."
note "macOS $(sw_vers -productVersion) on $(uname -m): OK"

step "Checking Apple's Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
    note "Not installed yet. A macOS dialog will appear: click Install and agree to the licence."
    note "This can take several minutes. Setup continues automatically when it finishes."
    xcode-select --install >/dev/null 2>&1 || true
    until xcode-select -p >/dev/null 2>&1 && command -v swiftc >/dev/null 2>&1; do sleep 10; done
fi
note "Installed: OK"

step "Building and installing the app (about a minute)"
./scripts/build.sh

step "Launching Lightsaber Cursor"
open "$HOME/Applications/Lightsaber Cursor.app"

print -P "\n%F{green}%BDone!%b%f Your pointer is now a lightsaber."
note "The first time the app starts it will:"
note "  • ask whether to start at login, and"
note "  • if macOS is hiding its menu bar icon, offer to open Menu Bar settings for you."
note "Toggle the saber any time with Control-Option-Command-L."
