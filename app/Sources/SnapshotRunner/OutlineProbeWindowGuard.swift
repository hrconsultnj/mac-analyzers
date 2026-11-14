import AppKit
import ToolWindows

/// The window guard of `OffscreenWindow` judged on real and on stand-in numbers. No window is ever ordered in
/// on a display: a window that is on a display is proved refused by handing the guard's judgement (the pure
/// `OffscreenWindow.reasons`) a parked window's real listed bounds with a display rectangle placed over them.
///   1. a parked window is let through once the window server lists it (it does so a moment after the window is
///      ordered in, so the guard waits for it, up to a second)
///   2. a frame on a display, never ordered in, is refused by its frame
///   3. the window server's bounds over a display are refused, whatever the frame says
///   4. an ordered-in window the server does not list, and a server that lists no display, are refused
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
        let parkedFrame = parked.frame
        let parkedListed = parked.listedBounds()
        parked.close()

        // 2. a frame on a display, never ordered in: refused by its frame alone
        guard let main = NSScreen.screens.first else { check("a display exists", false, "no screen"); return 1 }
        let framed = OffscreenWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        framed.setFrameOrigin(NSPoint(x: main.frame.minX + 100, y: main.frame.minY + 100))
        let framedReason = framed.onScreenReason()
        check("a frame on a display is refused before it is ordered in", framedReason?.contains("its frame") == true, framedReason ?? "NOT refused")
        framed.close()

        // 3. the server's bounds over a display (a display rectangle placed over the parked window's real bounds)
        guard let listed = parkedListed else { check("the parked window was listed", false, "not listed"); return 1 }
        let over = listed.insetBy(dx: -50, dy: -50)
        let overDisplay = OffscreenWindow.reasons(frame: parkedFrame, screenFrames: [], isOrderedIn: true, serverBounds: listed, displayBounds: [over])
        check("bounds over a display are refused by the window server's bounds", overDisplay.first?.contains("the window server puts it") == true, overDisplay.first ?? "NOT refused")
        let apart = OffscreenWindow.reasons(frame: parkedFrame, screenFrames: [], isOrderedIn: true, serverBounds: listed, displayBounds: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
        check("bounds away from every display pass", apart.isEmpty, apart.joined(separator: "; "))

        // 4. unconfirmed
        let unlisted = OffscreenWindow.reasons(frame: parkedFrame, screenFrames: [], isOrderedIn: true, serverBounds: nil, displayBounds: [over])
        check("an ordered-in window the server does not list is refused", unlisted.first?.contains("does not list") == true, unlisted.first ?? "NOT refused")
        let noDisplay = OffscreenWindow.reasons(frame: parkedFrame, screenFrames: [], isOrderedIn: true, serverBounds: listed, displayBounds: [])
        check("a server that lists no display is refused", noDisplay.first?.contains("no display") == true, noDisplay.first ?? "NOT refused")
        let notShown = OffscreenWindow.reasons(frame: parkedFrame, screenFrames: [], isOrderedIn: false, serverBounds: nil, displayBounds: [over])
        check("a window that is not ordered in needs no listing", notShown.isEmpty, notShown.joined(separator: "; "))
        return failed ? 1 : 0
    }
}
