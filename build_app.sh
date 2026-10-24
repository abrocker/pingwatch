#!/bin/bash
# Builds build/PingWatch.app
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/PingWatch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/PingWatch" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Fertig: $APP"
