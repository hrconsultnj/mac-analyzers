import AppKit
import CoreGraphics

/// The one window type every development tool uses (`SnapshotRunner`, `MenuSnapshot`, the outline
/// probes): a window that is drawn by the window server far outside every display, seen by nobody.
///
/// A plain titled `NSWindow` cannot be put there: AppKit constrains the frame of a titled window back
/// onto the main display when it is ordered in (the frame read `(0, -3, W, 672)`, the bottom-left corner of
/// the owner's screen), so this type returns the frame it is given. It places itself with `placeOffscreen()`,
/// which refuses to order the window in when its frame is on a display and checks again, with the window
/// server's own answer, as soon as it is ordered in: a window that touches a display, or that the window
/// server will not confirm, ends the tool with the reason, after it was visible for the length of that one
/// check and before anything is captured. Every tool calls `requireOffscreen(before:)` again before a capture.
///
/// This lives in its own target (`ToolWindows`, AppKit only) that only the tools depend on, so the app people
/// install does not contain it or its `exit`; `scripts/check.sh snapshot` fails if anything else uses it, and
/// if a tool makes a window or a modal panel any other way.
public final class OffscreenWindow: NSWindow {

    /// Far outside every display, and far from the `-9000` the invisible probes use.
    public static let origin = NSPoint(x: -30000, y: -30000)

    public override func constrainFrameRect(_ frame: NSRect, to screen: NSScreen?) -> NSRect { frame }

    /// Puts the window at `origin` and orders it in without activating the app, then sets the origin
    /// again (ordering a window in is where AppKit moves it, so the position is stated after, not only
    /// before) and checks where it really is. A frame that is already on a display stops the tool before the window is
    /// ordered in at all.
    public func placeOffscreen() {
        setFrameOrigin(Self.origin)
        if let reason = frameReason() { stop("show the window", reason) }
        orderFrontRegardless()
        setFrameOrigin(Self.origin)
        requireOffscreen(before: "keep the window shown")
    }

    /// Why the window's frame touches a screen; nil when it touches none.
    private func frameReason() -> String? {
        let hits = NSScreen.screens.filter { $0.frame.intersects(frame) }
        guard !hits.isEmpty else { return nil }
        return hits.map { "its frame \(NSStringFromRect(frame)) is on the display at \(NSStringFromRect($0.frame))" }
            .joined(separator: "; ")
    }

    /// The window server's own bounds for this window, or nil when it does not list it.
    private func serverBounds() -> CGRect? {
        let listed = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]]
        return (listed?.first?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    }

    /// The window server lists a window a moment after it is ordered in, not in the same turn: an ordered-in window
    /// that is not listed yet gets a bounded wait (up to a second, a run-loop turn at a time) before it counts as
    /// unconfirmed. Never longer, and never a pass: a window still unlisted after the wait is refused.
    private func waitForListing() -> CGRect? {
        let deadline = Date().addingTimeInterval(Self.listingWait)
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            if let rect = serverBounds() { return rect }
        } while Date() < deadline
        return nil
    }

    /// The longest the window server is given to list an ordered-in window.
    static let listingWait: TimeInterval = 1.0

    /// Why this window is, or may be, on a display; nil when it is nowhere near one. Judged two ways: the
    /// frame against every screen's frame, and the window server's bounds for the window against every active
    /// display's bounds. A window that is ordered in and that the window server does not list cannot be
    /// confirmed to be anywhere, which counts as being on a display.
    public func onScreenReason() -> String? {
        var reasons: [String] = []
        if let reason = frameReason() { reasons.append(reason) }
        if let rect = serverBounds() ?? (isVisible ? waitForListing() : nil) {
            // The ONLINE displays, not the active ones: while the screen is locked or asleep the active list is
            // empty, and a guard that compares against nothing refuses nothing.
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
            if count == 0 { reasons.append("the window server lists no display, so there is nothing to judge the window against") }
            for id in ids.prefix(Int(count)) where CGDisplayBounds(id).intersects(rect) {
                reasons.append("the window server puts it at \(rect.debugDescription), on display \(id)")
            }
        } else if isVisible {
            reasons.append("the window server does not list the window, so where it is cannot be confirmed")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }

    /// What a tool prints as its report of where the window is.
    public func placementReport() -> String {
        "window frame \(NSStringFromRect(frame)), window server bounds \(serverBounds().map { "\($0)" } ?? "not listed")"
    }

    /// The hard guard: a window that is on a display (or cannot be confirmed to be off every one) prints why
    /// and ends the tool with status 3, WITHOUT doing `what`.
    public func requireOffscreen(before what: String) {
        guard let reason = onScreenReason() else { return }
        stop(what, reason)
    }

    private func stop(_ what: String, _ reason: String) -> Never {
        FileHandle.standardError.write(Data("refusing to \(what): the tool's window is on a display (\(reason)). Nothing was captured.\n".utf8))
        exit(3)
    }
}
