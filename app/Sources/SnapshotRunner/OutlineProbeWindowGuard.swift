import AppKit
import ToolWindows

/// The window guard of `OffscreenWindow` judged on real windows: a window parked off every display is let
/// through once the window server lists it (it does so a moment after the window is ordered in, so the guard
/// waits for it, up to a second), and a window that IS on a display is refused, by its frame and by the window
/// server's bounds. The windows that sit on a display here are alpha 0 and ignore the mouse: nothing is drawn.
@MainActor
enum ProbeWindowGuard {
    static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        var failed = false
        func check(_ name: String, _ ok: Bool, _ detail: String) {
            say("\(ok ? "PASS" : "FAIL") windowguard \(name): \(detail)")
            if !ok { failed = true }
        }
        let size = NSSize(width: 300, height: 200)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable]

        // 1. parked off every display: ordered in, listed by the window server, confirmed off every display
        let parked = OffscreenWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        parked.placeOffscreen()          // would exit 3 itself if it were refused
        let parkedReason = parked.onScreenReason()
        check("a parked window is confirmed off every display", parkedReason == nil, parked.placementReport() + (parkedReason.map { " — \($0)" } ?? ""))
        parked.close()

        guard let main = NSScreen.screens.first else { check("a display exists", false, "no screen"); return 1 }
        let onDisplay = NSPoint(x: main.frame.minX + 100, y: main.frame.minY + 100)

        // 2. a frame on a display, never ordered in: refused by its frame alone
        let framed = OffscreenWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        framed.setFrameOrigin(onDisplay)
        let framedReason = framed.onScreenReason()
        check("a frame on a display is refused before it is ordered in", framedReason?.contains("its frame") == true, framedReason ?? "NOT refused")
        framed.close()

        // 3. ordered in on a display (alpha 0, click-through: nothing is drawn): refused by the window server's own bounds too
        let shown = OffscreenWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        shown.alphaValue = 0
        shown.ignoresMouseEvents = true
        shown.setFrameOrigin(onDisplay)
        shown.orderFrontRegardless()
        shown.setFrameOrigin(onDisplay)
        let shownReason = shown.onScreenReason()
        check("a window ordered in on a display is refused by the window server's bounds", shownReason?.contains("the window server puts it") == true, shownReason ?? "NOT refused")
        shown.close()
        return failed ? 1 : 0
    }
}
