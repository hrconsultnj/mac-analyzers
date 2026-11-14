import AppKit
import SwiftUI
import ToolWindows

/// The picture of a parked window (`OffscreenWindow.snapshotPNG`) judged on a split view with a sidebar list, which is
/// what the real screens are: the sidebar is a Liquid Glass surface that a plain `cacheDisplay` leaves empty, so the picture
/// must show the sidebar's surface and its labels, the title bar and the content, and be the size of the window.
@MainActor
enum ProbeSnapshot {
    static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        var failed = false
        func check(_ name: String, _ ok: Bool, _ detail: String) {
            say("\(ok ? "PASS" : "FAIL") snapshot \(name): \(detail)")
            if !ok { failed = true }
        }
        let content = NavigationSplitView {
            List { Text("Overview"); Text("Monitor"); Text("Spotlight") }
        } detail: {
            Text("Detail").frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Snapshot").toolbar { ToolbarItem { Button("Audit") {} } }
        }
        let window = OffscreenWindow(contentViewController: NSHostingController(rootView: content))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.placeOffscreen()
        _ = settle(); spin(1.0)
        window.requireOffscreen(before: "draw the snapshot probe")
        guard let png = window.snapshotPNG(), let rep = NSBitmapImageRep(data: png) else {
            check("a picture was drawn", false, "no picture"); return 1
        }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        let scale = Double(width) / window.frame.width
        check("the picture is the size of the window", abs(Double(height) / scale - window.frame.height) < 1.5, "\(width)x\(height) px for \(Int(window.frame.width))x\(Int(window.frame.height)) pt")

        // the sidebar column (the left 200 pt below the title bar): its surface is there, and labels are drawn on it
        func region(x: ClosedRange<Double>, y: ClosedRange<Double>) -> (opaque: Double, light: Double, distinct: Int) {
            var count = 0, opaque = 0, light = 0
            var seen = Set<Int>()
            for py in stride(from: Int(y.lowerBound * scale), to: Int(y.upperBound * scale), by: 2) {
                for px in stride(from: Int(x.lowerBound * scale), to: Int(x.upperBound * scale), by: 2) {
                    guard let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                    count += 1
                    if color.alphaComponent > 0.95 { opaque += 1 }
                    let value = Int((color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255)
                    seen.insert(value / 8)
                    if value > 150 { light += 1 }
                }
            }
            return (Double(opaque) / Double(max(count, 1)), Double(light) / Double(max(count, 1)), seen.count)
        }
        let sidebar = region(x: 10...190, y: 80...540)
        check("the sidebar's surface is drawn (not transparent)", sidebar.opaque > 0.98, "\(Int(sidebar.opaque * 100))% opaque")
        check("the sidebar's labels are drawn on it", sidebar.distinct >= 3, "\(sidebar.distinct) distinct tones")
        let detail = region(x: 300...880, y: 120...580)
        check("the content is drawn", detail.opaque > 0.98, "\(Int(detail.opaque * 100))% opaque")
        let titlebar = region(x: 10...190, y: 5...45)
        check("the title bar's traffic lights are drawn over the sidebar's surface", titlebar.distinct >= 2, "\(titlebar.distinct) distinct tones")
        window.close()
        return failed ? 1 : 0
    }
}
