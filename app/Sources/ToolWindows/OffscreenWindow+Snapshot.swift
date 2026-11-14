import AppKit
import CoreGraphics
import QuartzCore
import UniformTypeIdentifiers

/// The picture of an `OffscreenWindow`, drawn from its own views.
///
/// `screencapture -l <window>` images a window the window server has put on a display, and a window parked
/// on none cannot be imaged that way ("could not create image from window"): every render this project made
/// before the window was moved off-screen worked only because the window was on the owner's screen. This takes the
/// picture from the window's frame view (`contentView.superview`: the title bar, the toolbar, the sidebar and
/// the content), which needs no display, no screen-recording permission and no unlocked screen.
///
/// The views draw themselves (`cacheDisplay`). What the window server composites afterwards is not there, and some
/// surfaces are not drawn by a draw from above at all; those are drawn by hand (see `compositeGlass`). What still
/// differs from a screenshot of the same window on a display: the window's rounded corners, outer edge and shadow;
/// the blur and lens of the glass (the sidebar is a flat stand-in colour with its labels drawn over it); the bezel of
/// a dimmed button. `layer.render(in:)` was tried as the other way and draws less (no sidebar, no footer).
extension OffscreenWindow {

    /// The window as a PNG, at the window's backing scale; nil when it has no frame view or could not draw.
    public func snapshotPNG() -> Data? {
        guard let frameView = contentView?.superview else { return nil }
        pinGlassAppearance(in: frameView)
        frameView.layoutSubtreeIfNeeded()
        displayIfNeeded()
        let bounds = frameView.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        compositeGlass(in: frameView, onto: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes `snapshotPNG` to `url`; false when nothing could be drawn or written.
    @discardableResult
    public func writeSnapshot(to url: URL) -> Bool {
        guard let png = snapshotPNG() else { return false }
        return (try? png.write(to: url)) != nil
    }

    /// `cacheDisplay` draws nothing for an `NSGlassEffectView` (the Liquid Glass surface of the sidebar and the
    /// toolbar's groups): the glass and what is inside it are composited by the window server. So each glass view
    /// is drawn here by hand, over a flat stand-in for the glass, with its content view drawn on top of that. What
    /// the glass does to what is behind it (the blur, the lens, the specular edge) is NOT reproduced.
    /// A glass surface chooses light or dark from what is behind it; behind a window parked on no display there is
    /// nothing, and it chooses light, which turns the sidebar's labels black on a dark window. Each glass view is
    /// given the window's own appearance, and SwiftUI gets a short settle to redraw what is inside it.
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

    private func compositeGlass(in frameView: NSView, onto rep: NSBitmapImageRep) {
        var glass: [NSGlassEffectView] = []
        func collect(_ view: NSView) {
            for sub in view.subviews where !sub.isHidden {
                if let found = sub as? NSGlassEffectView { glass.append(found) }
                collect(sub)
            }
        }
        collect(frameView)
        guard !glass.isEmpty, let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        defer { context.flushGraphics() }
        for view in glass {
            // only the large surfaces (the sidebar): the toolbar's small groups are drawn by their own items
            guard view.bounds.height > 100 else { continue }
            var rect = view.convert(view.bounds, to: frameView)
            if frameView.isFlipped { rect.origin.y = frameView.bounds.height - rect.maxY }
            effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.underPageBackgroundColor.setFill()
                rect.fill()
                // the glass wrapper itself draws nothing, and the SwiftUI content inside it is skipped by a draw
                // from above: each part is drawn when asked directly, the list's table first (its visible part, above
                // the footer that sits over its bottom edge), then the hosting view (labels, footer) over it
                let parts: [(NSView, NSRect)] = [
                    Self.firstView(in: view, where: { $0 is NSTableView }).map { table in
                        var visible = table.visibleRect
                        if let scroll = table.enclosingScrollView {
                            let inset = scroll.contentInsets.bottom
                            if table.isFlipped { visible.size.height = max(0, visible.height - inset) }
                            else { visible.origin.y += inset; visible.size.height = max(0, visible.height - inset) }
                        }
                        return (table, visible)
                    },
                    Self.firstView(in: view, where: { String(describing: type(of: $0)).hasPrefix("NSHostingView") }).map { ($0, $0.bounds) },
                ].compactMap { $0 }
                for (content, visible) in parts {
                    guard !visible.isEmpty, let image = content.bitmapImageRepForCachingDisplay(in: visible) else { continue }
                    content.appearance = effectiveAppearance        // what the view would have drawn on the display
                    let table = content as? NSTableView
                    let selection = table?.selectionHighlightStyle ?? .none
                    // the system's highlight comes out of a draw like this as a solid black bar (it is a vibrant
                    // fill the glass would colour): it is left out of the table's draw and drawn by hand below
                    table?.selectionHighlightStyle = .none
                    content.cacheDisplay(in: visible, to: image)
                    table?.selectionHighlightStyle = selection
                    // Inside the glass the table's labels and symbols are vibrant: drawn as black with an alpha, which the
                    // glass fills with its label colour. Without the glass they stay black; on a dark window they are
                    // filled white here, the colour the glass gives them.
                    if table != nil, effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua { Self.fillVibrantMask(image) }
                    if let table, selection != .none {
                        for row in table.selectedRowIndexes {
                            var highlight = table.convert(table.rect(ofRow: row), to: frameView).insetBy(dx: 10, dy: 1)
                            if frameView.isFlipped { highlight.origin.y = frameView.bounds.height - highlight.maxY }
                            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                            (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.14 : 0.10).setFill()
                            NSBezierPath(roundedRect: highlight, xRadius: 8, yRadius: 8).fill()
                        }
                    }
                    var target = content.convert(visible, to: frameView)
                    if frameView.isFlipped { target.origin.y = frameView.bounds.height - target.maxY }
                    // source-over: the picture's transparent parts leave what is under them showing
                    let picture = NSImage(size: target.size)
                    picture.addRepresentation(image)
                    picture.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
        }
        // the sidebar's surface runs up behind the title bar: draw the title bar again over it (traffic lights, the
        // sidebar button, the toolbar), or the glass stand-in covers them
        if let bar = Self.firstView(in: frameView, where: { String(describing: type(of: $0)) == "NSTitlebarContainerView" }),
           let image = bar.bitmapImageRepForCachingDisplay(in: bar.bounds) {
            bar.cacheDisplay(in: bar.bounds, to: image)
            var target = bar.convert(bar.bounds, to: frameView)
            if frameView.isFlipped { target.origin.y = frameView.bounds.height - target.maxY }
            let picture = NSImage(size: target.size)
            picture.addRepresentation(image)
            picture.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}
