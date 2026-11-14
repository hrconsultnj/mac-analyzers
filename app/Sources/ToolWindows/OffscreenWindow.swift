import AppKit
import CoreGraphics
import QuartzCore

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
        let framed = Self.reasons(frame: frame, screenFrames: NSScreen.screens.map(\.frame), isOrderedIn: false,
                                  serverBounds: nil, displayBounds: [])
        if !framed.isEmpty { stop("show the window", framed.joined(separator: "; ")) }
        orderFrontRegardless()
        setFrameOrigin(Self.origin)
        requireOffscreen(before: "keep the window shown")
    }

    /// The judgement, with nothing read from the system: why a window is, or may be, on a display. Empty when it
    /// is nowhere near one. The frame is judged against every screen's frame; the window server's own bounds
    /// for it, against every online display's bounds. A window that is ordered in and that the window server
    /// does not list cannot be confirmed to be anywhere, and a server that lists no display leaves nothing to
    /// judge it against: both count as being on a display. Pure, so a probe can prove every refusal with
    /// numbers and without ever putting a window on a display.
    public static func reasons(frame: NSRect, screenFrames: [NSRect], isOrderedIn: Bool,
                               serverBounds: CGRect?, displayBounds: [CGRect]) -> [String] {
        var reasons: [String] = []
        for screen in screenFrames where screen.intersects(frame) {
            reasons.append("its frame \(NSStringFromRect(frame)) is on the display at \(NSStringFromRect(screen))")
        }
        if let rect = serverBounds {
            if displayBounds.isEmpty {
                reasons.append("the window server lists no display, so there is nothing to judge the window against")
            }
            for display in displayBounds where display.intersects(rect) {
                reasons.append("the window server puts it at \(rect.debugDescription), on the display at \(display.debugDescription)")
            }
        } else if isOrderedIn {
            reasons.append("the window server does not list the window, so where it is cannot be confirmed")
        }
        return reasons
    }

    /// The window server's own bounds for this window, or nil when it does not list it.
    public func listedBounds() -> CGRect? {
        let listed = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]]
        return (listed?.first?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    }

    /// The ONLINE displays, not the active ones: while the screen is locked or asleep the active list is empty,
    /// and a guard that compares against nothing refuses nothing.
    private static func onlineDisplayBounds() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// The window server lists a window a moment after it is ordered in, not in the same turn: an ordered-in window
    /// that is not listed yet gets a bounded wait (up to a second) before it counts as unconfirmed. The wait flushes
    /// this process's pending drawing to the window server and sleeps in short steps; it does not run the run loop,
    /// so nothing else (a timer, a queued block) runs inside a guard. Never longer, and never a pass: a window still
    /// unlisted after the wait is refused.
    private func waitForListing() -> CGRect? {
        let deadline = Date().addingTimeInterval(Self.listingWait)
        repeat {
            CATransaction.flush()
            usleep(10_000)
            if let rect = listedBounds() { return rect }
        } while Date() < deadline
        return nil
    }

    /// The longest the window server is given to list an ordered-in window.
    static let listingWait: TimeInterval = 1.0

    /// Why this window is, or may be, on a display; nil when it is nowhere near one (see `reasons`).
    public func onScreenReason() -> String? {
        let ordered = isVisible
        let listed = listedBounds() ?? (ordered ? waitForListing() : nil)
        let found = Self.reasons(frame: frame, screenFrames: NSScreen.screens.map(\.frame), isOrderedIn: ordered,
                                 serverBounds: listed, displayBounds: Self.onlineDisplayBounds())
        return found.isEmpty ? nil : found.joined(separator: "; ")
    }

    /// What a tool prints as its report of where the window is.
    public func placementReport() -> String {
        "window frame \(NSStringFromRect(frame)), window server bounds \(listedBounds().map { "\($0)" } ?? "not listed")"
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
