import AppKit
import Foundation
import SwiftUI
import UIComponents

/// `lifetime:<case>`: work the table queued for the next turn must do nothing when the table is gone.
/// A screen that replaces its table (a review whose preview just arrived) destroys the table's coordinator
/// while a fit, an update or the delivery of a selection, an expansion or a sort is still queued. Each case
/// causes one such thing, takes the table out of its window in the SAME turn, lets the loop run, and then
/// asserts that nothing crashed and that nothing was written to the caller's bindings by a table that no
/// longer exists. Each case runs in its own process (`scripts/outline-probe.sh check`): a crash is the
/// failure, and a crash must not take the other cases with it.
@MainActor
enum ProbeLifetime {
    static func run(_ name: String) -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3))
        let before = (model.expanded, model.selection, model.sortOrder.map(\.keyPath.hashValue))
        var caused = false
        autoreleasepool {
            let window = OffscreenWindow(contentViewController: NSHostingController(
                rootView: ProbeScreen(model: model, hosted: false, autosave: "probe-life-\(getpid())")))
            window.styleMask = [.titled, .resizable]
            window.setContentSize(NSSize(width: 700, height: 500))
            window.placeOffscreen()
            _ = settle(); spin(0.5)
            guard let outline = window.contentView.flatMap(findOutline(in:)) else { return }
            switch name {
            case "fit": window.setContentSize(NSSize(width: 520, height: 400)); caused = true            // a fit is queued
            case "selection": outline.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false); caused = true
            case "expansion": if let first = outline.item(atRow: 0) { outline.expandItem(first); caused = true }
            case "sort": outline.sortDescriptors = [NSSortDescriptor(key: "mem", ascending: false)]; caused = true
            default: break
            }
            // the table goes in the same turn: nothing the table queued has run yet
            window.contentViewController = nil
            window.close()
        }
        if name == "window" { return windowCase() }
        guard caused else { say("FAIL lifetime:\(name): unknown case or no table"); return 2 }
        spin(0.8); _ = settle()
        let after = (model.expanded, model.selection, model.sortOrder.map(\.keyPath.hashValue))
        let silent = before.0 == after.0 && before.1 == after.1 && before.2 == after.2
        say("\(silent ? "PASS" : "FAIL") lifetime:\(name): the table was gone before its queued work ran; no crash\(silent ? "" : ", but it wrote to the caller's bindings: expanded \(after.0.count) selection \(after.1.count)")")
        return silent ? 0 : 1
    }

    /// A fit scheduled while the table leaves its window must do nothing: the table has no room then, and
    /// a fit would save a collapsed width over the widths the person had (AppKit autosaves a width change).
    /// What the person set (a column's width) is what a table built afterwards finds.
    private static func windowCase() -> Int32 {
        let autosave = "probe-life-\(getpid())"
        let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3))
        func open(_ build: (NSOutlineView, OffscreenWindow) -> Void) {
            autoreleasepool {
                let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, autosave: autosave))
                build(harness.outline, harness.window)
                harness.window.contentViewController = nil
                harness.window.close()
            }
        }
        open { outline, window in
            outline.tableColumns[1].width = 133                        // the person's width, autosaved with a column move
            outline.tableColumns[2].isHidden = true
            outline.moveColumn(1, toColumn: 3)
            _ = settle(); spin(0.5); _ = settle()
            window.setContentSize(NSSize(width: 720, height: 500))     // a frame change queues a fit ... (the table leaves right after)

        }
        spin(0.8); _ = settle()
        var found: CGFloat = 0
        open { outline, _ in found = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("cpu"))?.width ?? 0 }
        let kept = Int(found.rounded()) == 133
        say("\(kept ? "PASS" : "FAIL") lifetime:window: a fit queued as the table left its window saved nothing over the person's width (CPU \(Int(found.rounded())), was 133)")
        return kept ? 0 : 1
    }
}
