import AppKit
import SwiftUI
import ToolWindows

/// The picture of a parked window (`OffscreenWindow.snapshotPNG`) judged on a split view with a sidebar list, a selected row and
/// a footer, which is what the real screens are, in a dark and in a light window. The sidebar is a Liquid Glass surface that a plain
/// `cacheDisplay` leaves empty, so the picture is judged by what must be in it, not by how many tones it has: the close button's
/// rectangle differs from the sidebar's surface, a known label's row has text pixels of the right polarity (light on dark, dark on
/// light), the selected row is lifted off the surface, the footer's text is there, and the content is drawn.
private struct SnapshotFixture: View {
    @State private var selection: String? = "Monitor"
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("Overview").tag("Overview")
                Text("Monitor").tag("Monitor")
                Text("Spotlight").tag("Spotlight")
            }
            .safeAreaInset(edge: .bottom) { Text("Footer label").padding() }
        } detail: {
            Text("Detail").frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Snapshot").toolbar { ToolbarItem { Button("Audit") {} } }
        }
    }
}

@MainActor
enum ProbeSnapshot {
    static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        var failed = false
        for dark in [true, false] where !judge(dark: dark) { failed = true }
        return failed ? 1 : 0
    }

    private static func judge(dark: Bool) -> Bool {
        let name = dark ? "dark" : "light"
        var ok = true
        func check(_ what: String, _ good: Bool, _ detail: String) {
            say("\(good ? "PASS" : "FAIL") snapshot \(name) \(what): \(detail)")
            if !good { ok = false }
        }
        let window = OffscreenWindow(contentViewController: NSHostingController(rootView: SnapshotFixture()))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.placeOffscreen()
        _ = settle(); spin(1.0)
        window.requireOffscreen(before: "draw the snapshot probe")
        defer { window.close() }
        let png: Data
        do { png = try window.snapshotPNG() } catch { check("a picture was made", false, "\(error)"); return false }
        guard let rep = NSBitmapImageRep(data: png), let frameView = window.contentView?.superview else {
            check("the picture decodes", false, "no picture"); return false
        }
        let scale = Double(rep.pixelsWide) / window.frame.width
        let height = window.frame.height
        check("the picture is the size of the window", abs(Double(rep.pixelsHigh) / scale - height) < 1.5, "\(rep.pixelsWide)x\(rep.pixelsHigh) px for \(Int(window.frame.width))x\(Int(height)) pt")

        // a rectangle in the frame view's coordinates (from the bottom) as a rectangle in the picture's (from the top), in points
        func inPicture(_ r: NSRect, of view: NSView) -> NSRect {
            let f = view.convert(r, to: frameView)
            return NSRect(x: f.minX, y: height - f.maxY, width: f.width, height: f.height)
        }
        func luminance(_ x: Double, _ y: Double) -> Double? {
            guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { return nil }
            return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        }
        /// the pixels of a rectangle whose luminance is `margin` or more away from `base`, toward light or toward dark
        func inked(_ r: NSRect, base: Double, towardLight: Bool, margin: Double = 0.3) -> Int {
            var n = 0
            for y in stride(from: r.minY, to: r.maxY, by: 0.5) {
                for x in stride(from: r.minX, to: r.maxX, by: 0.5) {
                    guard let l = luminance(x, y) else { continue }
                    if towardLight ? l > base + margin : l < base - margin { n += 1 }
                }
            }
            return n
        }
        func distinct(_ r: NSRect, from base: Double, by margin: Double) -> Int {
            var n = 0
            for y in stride(from: r.minY, to: r.maxY, by: 0.5) {
                for x in stride(from: r.minX, to: r.maxX, by: 0.5) {
                    if let l = luminance(x, y), abs(l - base) > margin { n += 1 }
                }
            }
            return n
        }

        // the sidebar's surface (its left edge, clear of rows and of the selection's inset)
        guard let fill = luminance(4, height / 2) else { check("the sidebar's surface is drawn", false, "transparent at the sidebar's edge"); return false }
        check("the sidebar's surface has the window's polarity", dark ? fill < 0.35 : fill > 0.65, "luminance \(String(format: "%.2f", fill))")

        // the close button (drawn by the title bar, over the sidebar's surface)
        if let close = window.standardWindowButton(.closeButton) {
            let r = inPicture(close.bounds, of: close)
            let n = distinct(r, from: fill, by: 0.06)
            check("the close button is drawn over the surface", n > 20, "\(n) pixels in \(Int(r.width))x\(Int(r.height)) pt differ from the surface")
        } else { check("the close button exists", false, "none") }

        // a known label's row and the selected row, from the sidebar's own table
        func tableOf(_ view: NSView) -> NSTableView? {
            if let t = view as? NSTableView { return t }
            for s in view.subviews { if let t = tableOf(s) { return t } }
            return nil
        }
        if let table = tableOf(frameView) {
            let rows = table.numberOfRows
            check("the sidebar has its rows", rows >= 3, "\(rows) rows")
            if rows >= 3 {
                let overview = inPicture(table.rect(ofRow: 0), of: table).insetBy(dx: 30, dy: 2)
                let n = inked(overview, base: fill, towardLight: dark)
                check("a known label (Overview) has \(dark ? "light" : "dark") text pixels", n > 30, "\(n) pixels")
                let selected = inPicture(table.rect(ofRow: 1), of: table)
                let lift = distinct(NSRect(x: selected.minX + 12, y: selected.minY + 2, width: 10, height: 4), from: fill, by: 0.04)
                check("the selected row is lifted off the surface", lift > 10, "\(lift) pixels differ from the surface")
                let text = inked(selected.insetBy(dx: 30, dy: 2), base: fill, towardLight: dark)
                check("the selected row's label is readable", text > 30, "\(text) \(dark ? "light" : "dark") pixels")
            }
        } else { check("the sidebar has a table", false, "none") }

        // the footer, over the bottom of the sidebar
        let footer = NSRect(x: 8, y: height - 70, width: 180, height: 62)
        let footerInk = inked(footer, base: fill, towardLight: dark)
        check("the footer's text is drawn", footerInk > 30, "\(footerInk) \(dark ? "light" : "dark") pixels")

        // the content
        guard let content = luminance(600, 300) else { check("the content is drawn", false, "transparent"); return false }
        check("the content is drawn", true, "luminance \(String(format: "%.2f", content))")
        return ok
    }
}
