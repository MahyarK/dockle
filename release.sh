#!/bin/sh
# Usage: ./release.sh 0.1.0  — universal build, DMG, and a GitHub release with the DMG attached.
set -e
cd "$(dirname "$0")"
V=${1:?usage: ./release.sh <version>}
VERSION=$V ARCHS="arm64 x86_64" ./build.sh
rm -rf dmg "Dockle-$V.dmg"
mkdir dmg && cp -R Dockle.app dmg/ && ln -s /Applications dmg/Applications
hdiutil create -volname Dockle -srcfolder dmg -ov -format UDZO "Dockle-$V.dmg" >/dev/null
rm -rf dmg
gh release create "v$V" "Dockle-$V.dmg" --title "Dockle $V" --notes "$(cat <<NOTES
Hover a Dock icon to see live previews of that app's windows, click one to raise it.

**Install**: open the DMG and drag Dockle to Applications. Requires macOS 14 or newer. Universal binary (Apple Silicon and Intel).

**First launch**: this build is not notarized, so macOS refuses to open it the first time. Open System Settings → Privacy & Security, scroll down, and click **Open Anyway** (on macOS 14, right-click Dockle and choose Open instead). Dockle then asks for Accessibility and Screen Recording; a setup window walks you through both.
NOTES
)"
