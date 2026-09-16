// Dockle — hover a Dock icon, get clickable window previews. Build with ./build.sh
import Cocoa
import ScreenCaptureKit

// ponytail: private but universal (AltTab and yabai use it too). Maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

let thumbMax: CGFloat = 260   // longest thumbnail side, in points
let hoverDelay = 0.15         // seconds a Dock icon must be hovered before capturing
let gap: CGFloat = 8

struct Thumb { let id: CGWindowID; let title: String; let image: CGImage; let size: NSSize }   // size in points
struct DockHit { let url: URL; let rect: CGRect }   // rect in Cocoa (bottom-left origin) coordinates

// MARK: - Accessibility helpers

func ax(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axRect(_ el: AXUIElement) -> CGRect? {
    guard let p = ax(el, kAXPositionAttribute), let s = ax(el, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

/// The running-app Dock item under the mouse, if any.
func dockItem(at mouse: NSPoint) -> DockHit? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
          let primary = NSScreen.screens.first else { return nil }
    let h = primary.frame.height   // AX uses a top-left origin on the primary screen; Cocoa uses bottom-left
    var el: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(dock.processIdentifier),
                                           Float(mouse.x), Float(h - mouse.y), &el) == .success,
          let el,
          ax(el, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
          ax(el, kAXIsApplicationRunningAttribute) as? Bool == true,
          let url = ax(el, kAXURLAttribute) as? URL,
          let r = axRect(el) else { return nil }
    return DockHit(url: url, rect: CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height))
}

func raiseWindow(pid: pid_t, windowID: CGWindowID) {
    let app = AXUIElementCreateApplication(pid)
    for w in (ax(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(w, &id) == .success, id == windowID else { continue }
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    NSRunningApplication(processIdentifier: pid)?.activate()
}

// MARK: - Capture

/// Windows of every process in `pids` (Wine and some PWAs spread one Dock icon over several processes).
func capture(pids: Set<pid_t>) async -> [Thumb] {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return [] }
    let windows = content.windows.filter {
        pids.contains($0.owningApplication?.processID ?? -1) && $0.windowLayer == 0
            && $0.frame.width > 64 && $0.frame.height > 64
            && ($0.isOnScreen || !($0.title ?? "").isEmpty)   // off-screen untitled windows are helper junk
    }
    var thumbs: [Thumb] = []
    for w in windows {
        let cfg = SCStreamConfiguration()
        let scale = min(1, thumbMax / max(w.frame.width, w.frame.height))
        cfg.width = Int(w.frame.width * scale * 2)   // 2x for retina
        cfg.height = Int(w.frame.height * scale * 2)
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        // ScreenCaptureKit refuses windows sitting in other fullscreen/tiled Spaces (error -3811); the deprecated CG call still gets them.
        guard let img = (try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg))
                ?? CGWindowListCreateImage(.null, .optionIncludingWindow, w.windowID, [.boundsIgnoreFraming, .nominalResolution]) else { continue }
        thumbs.append(Thumb(id: w.windowID, title: w.title ?? "", image: img, size: NSSize(width: w.frame.width * scale, height: w.frame.height * scale)))
    }
    return thumbs
}

// MARK: - Controller

final class Controller: NSObject {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    var current: URL?
    var keep = CGRect.zero   // the mouse may roam here without closing the preview
    var gen = 0              // bumped on every hover change; stale async work checks it
    var lastMouse = NSPoint.zero
    var stack = NSStackView()

    override init() {
        super.init()
        panel.level = .popUpMenu   // above the Dock
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .vibrantDark)
        // ponytail: 30 Hz mouse poll instead of event monitors; one code path, works over our own panel too.
        Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [self] _ in tick() }
    }

    func tick() {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastMouse else { return }
        lastMouse = mouse
        if let hit = dockItem(at: mouse) {
            guard hit.url != current else { return }
            current = hit.url
            keep = hit.rect
            gen += 1
            let g = gen
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay) { if g == self.gen { self.show(hit, gen: g) } }
        } else if current != nil, !keep.contains(mouse) {
            hide()
        }
    }

    func hide() {
        current = nil
        gen += 1
        panel.orderOut(nil)
    }

    func show(_ hit: DockHit, gen g: Int) {
        guard let bundleID = Bundle(url: hit.url)?.bundleIdentifier else { return }
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
        guard !pids.isEmpty else { return }
        Task { @MainActor [self] in
            var shown = Set<CGWindowID>()
            while g == gen {   // live: re-capture ~5x/s until the hover ends
                let thumbs = await capture(pids: pids)
                guard g == gen else { return }
                if thumbs.isEmpty { panel.orderOut(nil); return }   // nothing to show; also drops a previous app's stale panel
                if Set(thumbs.map(\.id)) != shown {          // window set changed: rebuild
                    shown = Set(thumbs.map(\.id))
                    layout(thumbs, near: hit.rect)
                } else {                                      // same windows: swap images in place, buttons survive
                    let byID = Dictionary(uniqueKeysWithValues: thumbs.map { ($0.id, $0) })
                    for case let b as NSButton in stack.arrangedSubviews {
                        guard let t = byID[CGWindowID(b.tag)] else { continue }
                        b.image = image(t)
                        b.title = t.title
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func image(_ t: Thumb) -> NSImage { NSImage(cgImage: t.image, size: t.size) }

    func layout(_ thumbs: [Thumb], near item: CGRect) {
        stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        for t in thumbs {
            let img = image(t)
            let b = NSButton(title: t.title, image: img, target: self, action: #selector(click))
            b.imagePosition = .imageAbove
            b.isBordered = false
            b.font = .systemFont(ofSize: 11)
            b.lineBreakMode = .byTruncatingTail
            b.tag = Int(t.id)
            b.widthAnchor.constraint(equalToConstant: img.size.width).isActive = true
            stack.addArrangedSubview(b)
        }
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12
        fx.layer?.masksToBounds = true
        fx.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor), stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor), stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        panel.contentView = fx
        let size = stack.fittingSize
        panel.setContentSize(size)

        // Sit next to the Dock item on whichever screen edge the Dock lives.
        // ponytail: no scrolling; a Dock icon with 8+ windows gets clipped at the screen edge.
        let screen = (NSScreen.screens.first { $0.frame.intersects(item) } ?? NSScreen.main ?? NSScreen.screens[0]).frame
        var origin: NSPoint
        if item.midY < screen.minY + screen.height * 0.25 {     // bottom
            origin = NSPoint(x: item.midX - size.width / 2, y: item.maxY + gap)
        } else if item.midX < screen.midX {                    // left
            origin = NSPoint(x: item.maxX + gap, y: item.midY - size.height / 2)
        } else {                                               // right
            origin = NSPoint(x: item.minX - gap - size.width, y: item.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, screen.minX + gap), screen.maxX - size.width - gap)
        origin.y = min(max(origin.y, screen.minY + gap), screen.maxY - size.height - gap)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        keep = panel.frame.union(item).insetBy(dx: -gap, dy: -gap)
    }

    @objc func click(_ sender: NSButton) {
        let id = CGWindowID(sender.tag)
        let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first
        if let pid = info?[kCGWindowOwnerPID as String] as? pid_t { raiseWindow(pid: pid, windowID: id) }
        hide()
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
CGRequestScreenCaptureAccess()
NSLog("Dockle start: accessibility=%d screenRecording=%d", AXIsProcessTrusted(), CGPreflightScreenCaptureAccess())
if !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() {   // nothing works until both are granted; say so instead of failing silently
    let alert = NSAlert()
    alert.messageText = "Dockle needs two permissions"
    alert.informativeText = """
        Accessibility (to read the Dock): \(AXIsProcessTrusted() ? "granted" : "missing")
        Screen Recording (to capture windows): \(CGPreflightScreenCaptureAccess() ? "granted" : "missing")

        Enable Dockle under both in System Settings > Privacy & Security, then relaunch Dockle.
        """
    alert.addButton(withTitle: "Open Accessibility")
    alert.addButton(withTitle: "Open Screen Recording")
    alert.addButton(withTitle: "Later")
    NSApp.activate()
    let r = alert.runModal()
    if r != .alertThirdButtonReturn {
        let pane = r == .alertFirstButtonReturn ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
status.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Dockle")
status.menu = NSMenu()
status.menu?.addItem(withTitle: "Quit Dockle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let controller = Controller()
app.run()
