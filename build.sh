#!/bin/sh
# Builds Dockle.app next to this script.  Run: ./build.sh && open Dockle.app
# VERSION=1.2.3 sets the bundle version; ARCHS="arm64 x86_64" builds a universal binary (release.sh does both).
set -e
cd "$(dirname "$0")"
APP=Dockle.app
VERSION=${VERSION:-0.0.0}
ARCHS=${ARCHS:-$(uname -m)}
T=$(mktemp -d)
for a in $ARCHS; do swiftc -O -target "$a-apple-macos14.0" -o "$T/$a" main.swift; done
mkdir -p "$APP/Contents/MacOS"
lipo -create "$T"/* -output "$APP/Contents/MacOS/Dockle"
rm -rf "$T"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mahyark.dockle</string>
<key>CFBundleName</key><string>Dockle</string>
<key>CFBundleExecutable</key><string>Dockle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Sign with a real dev cert if one exists so TCC grants survive rebuilds; ad-hoc otherwise.
ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')
codesign --force --sign "${ID:--}" "$APP" 2>&1 | grep -v "replacing existing signature" || true
echo "built $APP $VERSION ($ARCHS; signed: ${ID:-ad-hoc})"
