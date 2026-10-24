#!/bin/bash
# Builds a universal PingWatch.app and packs it as dist/PingWatch-<version>.zip for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./build_app.sh
mkdir -p dist
ZIP="dist/PingWatch-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/PingWatch.app "$ZIP"
echo "Architekturen: $(lipo -archs build/PingWatch.app/Contents/MacOS/PingWatch)"
shasum -a 256 "$ZIP"
