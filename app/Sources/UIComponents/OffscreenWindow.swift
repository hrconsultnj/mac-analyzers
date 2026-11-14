import AppKit
import CoreGraphics

/// The one window type every development tool uses (`SnapshotRunner`, `MenuSnapshot`, the outline
/// probes): a window that is drawn by the window server far outside every display, seen by nobody.
///
/// A plain titled `NSWindow` cannot be put there: AppKit constrains the frame of a titled window back
/// onto the main display when it is ordered in (the frame read `(0, -3, W, 672)`, the bottom-left corner of
/// the owner's screen), so this type returns the frame it is given. It places itself with `placeOffscreen()`
/// and every tool calls `requireOffscreen(before:)` before it captures: a window that touches a display
/// stops the tool, with the reason, before anything is drawn for anyone to see. Nothing in the app people
/// install uses this type; `scripts/check.sh offscreen` fails if a tool makes a window any other way.
public final class OffscreenWindow: NSWindow {

    /// Far outside every display, and far from the `-9000` the invisible probes use.
    public static let origin = NSPoint(x: -30000, y: -30000)

    public override func constrainFrameRect(_ frame: NSRect, to screen: NSScreen?) -> NSRect { frame }

    /// Puts the window at `origin` and orders it in without activating the app, then sets the origin
    /// again: ordering a window in is where AppKit moves it, so the position is stated after, not only before.
    public func placeOffscreen() {
        setFrameOrigin(Self.origin)
        orderFrontRegardless()
        setFrameOrigin(Self.origin)
    }

    /// Why this window is, or may be, on a display; nil when it is nowhere near one. Judged two ways: the
    /// frame against every screen's frame, and the window server's own bounds for the window against
    /// every active display's bounds.
    public func onScreenReason() -> String? {
        var reasons: [String] = []
        for screen in NSScreen.screens where screen.frame.intersects(frame) {
            reasons.append("its frame \(NSStringFromRect(frame)) is on the display at \(NSStringFromRect(screen.frame))")
        }
        let listed = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]]
        if let info = listed?.first, let bounds = info[kCGWindowBounds as String] as? [String: Any],
           let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
            for id in ids.prefix(Int(count)) where CGDisplayBounds(id).intersects(rect) {
                reasons.append("the window server puts it at \(rect.debugDescription), on display \(id)")
            }
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }

    /// What a tool prints as its report of where the window is.
    public func placementReport() -> String {
        let listed = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]]
        let server = (listed?.first?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            .map { "\($0)" } ?? "not listed"
        return "window frame \(NSStringFromRect(frame)), window server bounds \(server)"
    }

    /// The hard guard: call it after the window is ordered in and immediately before every capture. A window
    /// that is on a display prints why and ends the tool with status 3, WITHOUT capturing.
    public func requireOffscreen(before what: String) {
        guard let reason = onScreenReason() else { return }
        FileHandle.standardError.write(Data("refusing to \(what): the tool's window is on a display (\(reason)). Nothing was captured.\n".utf8))
        exit(3)
    }
}
