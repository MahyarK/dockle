# Dockle

Hover a Dock icon on macOS to see live thumbnails of that app's windows, click one to raise it. One file, no dependencies.

## Build

```bash
./build.sh
open Dockle.app
```

On first launch a setup window asks for **Accessibility** (to read the Dock) and **Screen Recording** (to capture windows), with a button to the right Settings pane for each. It stays open until both are granted, then closes itself and relaunches Dockle.

## How it works

- Polls the mouse and asks the Dock's accessibility tree which running app's icon is underneath it.
- After a short hover delay, captures that app's windows with ScreenCaptureKit and shows them as clickable thumbnails in a small panel above the Dock.
- Keeps re-capturing while the panel is open, so previews stay live.
- Clicking a thumbnail raises that window.

No Xcode project, no dependencies — one Swift file built with `swiftc`.

## License

MIT, see [LICENSE](LICENSE).
