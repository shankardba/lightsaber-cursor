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

step "Checking for a previous installation"
bundle_id="com.shankar.lightsabercursor"
old_apps=()
for dir in "$HOME/Applications" "/Applications"; do
    [[ -d "$dir/Lightsaber Cursor.app" ]] && old_apps+=("$dir/Lightsaber Cursor.app")
done
has_settings=false
defaults read "$bundle_id" >/dev/null 2>&1 && has_settings=true
fresh=false
if (( ${#old_apps} )) || $has_settings || pgrep -x LightsaberCursor >/dev/null; then
    note "Found one. It will be removed and replaced with this version."
    # LIGHTSABER_SETTINGS=keep|fresh answers the question below without a dialog.
    choice="${LIGHTSABER_SETTINGS:-}"
    if [[ -z "$choice" ]] && $has_settings; then
        button=$(osascript -e 'button returned of (display dialog "A previous installation of Lightsaber Cursor was found. It will be removed and replaced with this version.

Keep your saved sabers and settings?" buttons {"Start Fresh", "Keep Settings"} default button "Keep Settings" with title "Lightsaber Cursor setup" with icon note)' 2>/dev/null) || button="Keep Settings"
        [[ "$button" == "Start Fresh" ]] && choice=fresh
    fi
    [[ "$choice" == "fresh" ]] && fresh=true

    # Quitting (or the app ending any other way) gives the normal pointer back straight away.
    pkill -x LightsaberCursor 2>/dev/null && sleep 1 || true
    for app in "${old_apps[@]}"; do
        rm -rf "$app" 2>/dev/null || note "Couldn't remove $app (drag it to the Trash yourself)."
    done
    rm -rf "$HOME/Library/Caches/lightsaber-cursor-build"
    # Older versions asked for Accessibility; this version doesn't need it.
    tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1 || true
    if $fresh; then
        defaults delete "$bundle_id" >/dev/null 2>&1 || true
        note "Settings cleared; the app will ask its first-run questions again."
    else
        note "Your sabers and settings are kept."
    fi
else
    note "None found: fresh install."
fi

step "Building and installing the app (about a minute)"
./scripts/build.sh
if $fresh; then
    # Starting fresh also forgets "start at login"; the app asks again on first launch.
    "$HOME/Applications/Lightsaber Cursor.app/Contents/MacOS/LightsaberCursor" --login-item off
fi

first_run=true
defaults read com.shankar.lightsabercursor hasLaunched >/dev/null 2>&1 && first_run=false

step "Launching Lightsaber Cursor"
open "$HOME/Applications/Lightsaber Cursor.app"

print -P "\n%F{green}%BDone!%b%f Your pointer is now a lightsaber."
if $first_run; then
    note "The first time the app starts it will:"
    note "  • ask whether to start at login, and"
    note "  • if macOS is hiding its menu bar icon, offer to open Menu Bar settings for you."
fi
note "Toggle the saber any time with Control-Option-Command-L."
