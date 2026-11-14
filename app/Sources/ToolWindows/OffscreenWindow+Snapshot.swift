import AppKit
import CoreGraphics
import QuartzCore
import UniformTypeIdentifiers

/// Why a picture could not be made. A tool that gets one prints it and ends non-zero: a picture with a step silently
/// skipped is a wrong picture that looks like a right one.
public struct SnapshotError: Error, CustomStringConvertible {
    public let description: String
    init(_ text: String) { description = text }
}

/// The picture of an `OffscreenWindow`, drawn from its own views.
///
/// `screencapture -l <window>` images a window the window server has put on a display, and a window parked
/// on none cannot be imaged that way ("could not create image from window"): every render this project made
/// before the window was moved off-screen worked only because the window was on the owner's screen. This takes the
/// picture from the window's frame view (`contentView.superview`: the title bar, the toolbar, the sidebar and
/// the content), which needs no display, no screen-recording permission and no unlocked screen.
///
/// The views draw themselves (`cacheDisplay`). What the window server composites afterwards is not there, and some
/// surfaces are not drawn by a draw from above at all; those are drawn by hand (see `compositeGlass`). The picture is
/// therefore PARTLY INVENTED, and CLAUDE.md lists what is: the glass is a flat stand-in colour, the sidebar's selection is
/// drawn by hand, a dark window's sidebar labels are recoloured, the glass is told the window's appearance and given a
/// short settle, the window is never key, and only glass larger than 100 pt is drawn. Parts are found by what they are
/// (the close button's ancestor, the glass's `contentView`, an `NSTableView`), never by a private class name; a part
/// that cannot be found is an error, not a skipped step.
extension OffscreenWindow {

    /// The window as a PNG, at the window's backing scale. Throws `SnapshotError` when a part of the picture cannot
    /// be found or drawn.
    public func snapshotPNG() throws -> Data {
        guard let frameView = contentView?.superview else { throw SnapshotError("the window has no frame view") }
        pinGlassAppearance(in: frameView)
        frameView.layoutSubtreeIfNeeded()
        displayIfNeeded()
        let bounds = frameView.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { throw SnapshotError("the frame view has nothing to draw into") }
        frameView.cacheDisplay(in: bounds, to: rep)
        try compositeGlass(in: frameView, onto: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError("the picture could not be encoded") }
        return png
    }

    /// Writes `snapshotPNG` to `url`; throws `SnapshotError` (or the write's own error).
    public func writeSnapshot(to url: URL) throws {
        try snapshotPNG().write(to: url)
    }

    /// A glass surface chooses light or dark from what is behind it; behind a window parked on no display there is
    /// nothing, and it chooses light, which turns the sidebar's labels black on a dark window. Each glass view is
    /// given the window's own appearance (this is something the picture does that the real window does not), and the
    /// run loop is spun for 0.4 s so SwiftUI redraws what is inside it.
    private func pinGlassAppearance(in frameView: NSView) {
        var changed = false
        func visit(_ view: NSView) {
            if view is NSGlassEffectView, view.appearance != effectiveAppearance { view.appearance = effectiveAppearance; changed = true }
            view.subviews.forEach(visit)
        }
        visit(frameView)
        if changed { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
    }

    /// Turns a picture drawn as black-with-alpha (a vibrant mask) into white-with-alpha, keeping the alpha: the
    /// colour the glass fills such content with on a dark window.
    private static func fillVibrantMask(_ rep: NSBitmapImageRep) {
        guard rep.bitsPerSample == 8, rep.samplesPerPixel == 4, !rep.isPlanar, let data = rep.bitmapData else { return }
        let alphaFirst = rep.bitmapFormat.contains(.alphaFirst)
        for row in 0..<rep.pixelsHigh {
            var pixel = data + row * rep.bytesPerRow
            for _ in 0..<rep.pixelsWide {
                let alpha = alphaFirst ? pixel[0] : pixel[3]
                let r = alphaFirst ? pixel[1] : pixel[0], g = alphaFirst ? pixel[2] : pixel[1], b = alphaFirst ? pixel[3] : pixel[2]
                if alpha > 0, r < 8, g < 8, b < 8 {            // black, premultiplied: white at this alpha is (alpha, alpha, alpha)
                    if alphaFirst { pixel[1] = alpha; pixel[2] = alpha; pixel[3] = alpha } else { pixel[0] = alpha; pixel[1] = alpha; pixel[2] = alpha }
                }
                pixel += 4
            }
        }
    }

    private static func firstView(in view: NSView, where matches: (NSView) -> Bool) -> NSView? {
        for sub in view.subviews {
            if matches(sub) { return sub }
            if let found = firstView(in: sub, where: matches) { return found }
        }
        return nil
    }

    /// `cacheDisplay` draws nothing for an `NSGlassEffectView` (the Liquid Glass surface of the sidebar): the glass and what
    /// is inside it are composited by the window server. So each large glass surface is drawn here by hand, over a flat
    /// stand-in for the glass, with its table and content drawn on top of that, and the title bar drawn again over all of it.
    /// What the glass does to what is behind it (the blur, the lens, the specular edge) is NOT reproduced.
    private func compositeGlass(in frameView: NSView, onto rep: NSBitmapImageRep) throws {
        var glass: [NSGlassEffectView] = []
        func collect(_ view: NSView) {
            for sub in view.subviews where !sub.isHidden {
                if let found = sub as? NSGlassEffectView { glass.append(found) }
                collect(sub)
            }
        }
        collect(frameView)
        // only the large surfaces (the sidebar): the toolbar's small glass groups are drawn by their own items
        let surfaces = glass.filter { $0.bounds.height > 100 }
        guard !surfaces.isEmpty else { return }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw SnapshotError("the picture cannot be drawn into") }
        // the title bar is the frame view's child that holds the close button, whatever its class is called
        guard let close = standardWindowButton(.closeButton) else { throw SnapshotError("the window has no close button to find its title bar by") }
        var bar: NSView = close
        while let up = bar.superview, up !== frameView { bar = up }
        guard bar.superview === frameView else { throw SnapshotError("the close button is not under the window's frame view") }
        for view in surfaces where view.contentView == nil { throw SnapshotError("a \(Int(view.bounds.height)) pt glass surface has no content view to draw") }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { context.flushGraphics(); NSGraphicsContext.restoreGraphicsState() }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        func place(_ rect: NSRect, in view: NSView) -> NSRect {
            var target = view.convert(rect, to: frameView)
            if frameView.isFlipped { target.origin.y = frameView.bounds.height - target.maxY }
            return target
        }
        func draw(_ image: NSBitmapImageRep, in target: NSRect) {
            // source-over: the picture's transparent parts leave what is under them showing
            let picture = NSImage(size: target.size)
            picture.addRepresentation(image)
            picture.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
        for view in surfaces {
            guard let content = view.contentView else { continue }
            effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.underPageBackgroundColor.setFill()
                place(view.bounds, in: view).fill()
                // the glass wrapper itself draws nothing, and what is inside it is skipped by a draw from above: the
                // list's table is drawn when asked directly (its visible part, above a footer that sits over its
                // bottom edge), then the content view (labels, footer) over it
                if let table = Self.firstView(in: content, where: { $0 is NSTableView }) as? NSTableView {
                    var visible = table.visibleRect
                    if let scroll = table.enclosingScrollView {
                        let inset = scroll.contentInsets.bottom
                        if !table.isFlipped { visible.origin.y += inset }
                        visible.size.height = max(0, visible.height - inset)
                    }
                    let selection = table.selectionHighlightStyle
                    if !visible.isEmpty, let image = table.bitmapImageRepForCachingDisplay(in: visible) {
                        table.appearance = effectiveAppearance        // what the view would have drawn on the display
                        // the system's highlight comes out of a draw like this as a solid black bar (a vibrant fill the
                        // glass would colour): it is left out of the draw and drawn by hand below
                        table.selectionHighlightStyle = .none
                        table.cacheDisplay(in: visible, to: image)
                        table.selectionHighlightStyle = selection
                        // Inside the glass the labels and symbols are vibrant: drawn black with an alpha, which the glass
                        // fills with its label colour. On a dark window they are filled white here. This recolours every
                        // near-black pixel of the table, so a label that is hard-coded black would be recoloured too.
                        if dark { Self.fillVibrantMask(image) }
                        if selection != .none {
                            for row in table.selectedRowIndexes {
                                let highlight = place(table.rect(ofRow: row), in: table).insetBy(dx: 10, dy: 1)
                                (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.14 : 0.10).setFill()
                                NSBezierPath(roundedRect: highlight, xRadius: 8, yRadius: 8).fill()
                            }
                        }
                        draw(image, in: place(visible, in: table))
                    }
                }
                if let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.appearance = effectiveAppearance
                    content.cacheDisplay(in: content.bounds, to: image)
                    draw(image, in: place(content.bounds, in: content))
                }
            }
        }
        // the sidebar's surface runs up behind the title bar: draw the title bar again over it (traffic lights, the
        // sidebar button, the toolbar), or the glass stand-in covers them
        guard let image = bar.bitmapImageRepForCachingDisplay(in: bar.bounds) else { throw SnapshotError("the title bar has nothing to draw into") }
        bar.cacheDisplay(in: bar.bounds, to: image)
        draw(image, in: place(bar.bounds, in: bar))
    }
}
