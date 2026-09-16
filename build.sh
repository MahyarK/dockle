#!/bin/sh
# Builds Dockle.app next to this script.  Run: ./build.sh && open Dockle.app
# First launch asks for Accessibility (to read the Dock) and Screen Recording (to capture windows).
# Grant both in System Settings > Privacy & Security, then relaunch the app.
set -e
cd "$(dirname "$0")"
APP=Dockle.app
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target "$(uname -m)-apple-macos14.0" -o "$APP/Contents/MacOS/Dockle" main.swift
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mahyark.dockle</string>
<key>CFBundleName</key><string>Dockle</string>
<key>CFBundleExecutable</key><string>Dockle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
# Sign with a real dev cert if one exists so TCC grants survive rebuilds; ad-hoc otherwise.
ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')
codesign --force --sign "${ID:--}" "$APP"
echo "built $APP (signed: ${ID:-ad-hoc})"
