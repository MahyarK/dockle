# Dockle

Hover a Dock icon on macOS to see live thumbnails of that app's windows, click one to raise it. One file, no dependencies.

## Build

```bash
./build.sh
open Dockle.app
```

First launch asks for **Accessibility** (to read the Dock) and **Screen Recording** (to capture windows). Grant both in System Settings → Privacy & Security, then relaunch.

## How it works

- Polls the mouse and asks the Dock's accessibility tree which running app's icon is underneath it.
- After a short hover delay, captures that app's windows with ScreenCaptureKit and shows them as clickable thumbnails in a small panel above the Dock.
- Keeps re-capturing while the panel is open, so previews stay live.
- Clicking a thumbnail raises that window.

No Xcode project, no dependencies — one Swift file built with `swiftc`.

## License

MIT, see [LICENSE](LICENSE).
