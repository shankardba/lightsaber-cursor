#!/bin/zsh
# Builds "Lightsaber Cursor.app" with swiftc directly (SwiftPM isn't needed) and installs it to ~/Applications.
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$HOME/Library/Caches/lightsaber-cursor-build"
APP_NAME="Lightsaber Cursor"
BUNDLE_ID="com.shankar.lightsabercursor"
APP="$BUILD/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

mkdir -p "$BUILD"
echo "Compiling…"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
    -framework AppKit -framework SwiftUI -framework Carbon \
    -framework ApplicationServices -framework ServiceManagement \
    "$ROOT"/Sources/LightsaberCursor/*.swift \
    -o "$BUILD/LightsaberCursor"

if [[ "${1:-}" == "--binary-only" ]]; then
    echo "Built $BUILD/LightsaberCursor"
    exit 0
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/LightsaberCursor" "$APP/Contents/MacOS/LightsaberCursor"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>LightsaberCursor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# A stable self-signed identity keeps macOS privacy grants (Accessibility) across rebuilds; ad-hoc is the fallback.
SIGN_NAME="Lightsaber Cursor Local Signing"
SIGN_ID=$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$SIGN_NAME\"" 'index($0, n) {print $2; exit}')
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
else
    echo "warning: '$SIGN_NAME' certificate not found; ad-hoc signing (Accessibility must be re-granted after each rebuild)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

mkdir -p "$INSTALL_DIR"
pkill -x LightsaberCursor 2>/dev/null || true
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/"
echo "Installed $INSTALL_DIR/$APP_NAME.app"
