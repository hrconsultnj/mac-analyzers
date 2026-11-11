import AppKit
import Foundation
import SwiftUI
import UIComponents

/// `fit`: columns that declare how they give way to room (`OutlineColumnFit`), in a window that is
/// made narrower and wider. At every width every ESSENTIAL column is entirely inside the visible
/// rect; optional columns go rightmost first, come back leftmost first, stay in the header's menu,
/// and a person's choice from that menu is kept.
@MainActor
enum ProbeFit {
    private struct Screen: View {
        let model: ProbeModel
        let autosave: String
        var body: some View {
            OutlineTable(model.rows, children: \.children, selection: Bindable(model).selection,
                         sortOrder: Bindable(model).sortOrder, expanded: Bindable(model).expanded, autosave: autosave) {
                OutlineColumn("name", "Name", text: { $0.name }, sortUsing: KeyPathComparator(\ProbeRow.name))
                    .width(min: 200, ideal: 260)
                OutlineColumn("cpu", "CPU", text: { probeFormat($0.cpu) }).alignment(.trailing).width(min: 130, ideal: 140)
                OutlineColumn("mem", "Memory", text: { "\($0.mem) MB" }).alignment(.trailing).width(min: 130, ideal: 130)
                OutlineColumn("kind", "Kind", text: { $0.kind }).width(min: 140, ideal: 160).fit(.optional)
                OutlineColumn("owner", "Owner", text: { _ in "me" }).width(min: 140, ideal: 160).fit(.optional)
            }
        }
    }

    static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = ProbeModel(rows: makeProbeRows(parents: 10, kids: 2))
        let autosave = "probe-fit-\(getpid())"
        let host = NSHostingController(rootView: Screen(model: model, autosave: autosave))
        let window = ProbeWindow(contentViewController: host)
        window.styleMask = [.titled, .resizable]
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFrontRegardless()
        var ok = true
        func verdict(_ good: Bool, _ text: String) { say((good ? "PASS " : "FAIL ") + text); if !good { ok = false } }
        func at(_ width: CGFloat) -> NSOutlineView? {
            window.setContentSize(NSSize(width: width, height: 500))
            _ = settle(); spin(0.4); _ = settle()
            let found = window.contentView.flatMap(findOutline(in:))
            say("  window \(Int(window.contentView?.bounds.width ?? 0)) clip \(Int(found?.enclosingScrollView?.contentView.bounds.width ?? 0)) widths \(found?.tableColumns.map { "\($0.identifier.rawValue)=\(Int($0.width))\($0.isHidden ? "h" : "")" } ?? [])")
            return found
        }
        func shown(_ outline: NSOutlineView) -> [String] { outline.tableColumns.filter { !$0.isHidden }.map(\.identifier.rawValue) }
        func inside(_ outline: NSOutlineView, _ id: String) -> Bool {
            let index = outline.column(withIdentifier: NSUserInterfaceItemIdentifier(id))
            guard index >= 0 else { return false }
            let rect = outline.rect(ofColumn: index)
            if !(rect.minX >= outline.visibleRect.minX - 0.5 && rect.maxX <= outline.visibleRect.maxX + 0.5) { say("  \(id) column \(rect) visible \(outline.visibleRect)") }
            return rect.minX >= outline.visibleRect.minX - 0.5 && rect.maxX <= outline.visibleRect.maxX + 0.5
        }
        func essentialsVisible(_ outline: NSOutlineView) -> Bool { ["name", "cpu", "mem"].allSatisfy { inside(outline, $0) } }

        guard let outline = at(1100) else { say("FAIL no table"); return 1 }
        verdict(shown(outline) == ["name", "cpu", "mem", "kind", "owner"] && essentialsVisible(outline), "1100: every column shows, \(shown(outline))")
        _ = at(760)
        verdict(essentialsVisible(outline) && !shown(outline).contains("owner"), "760: essentials inside the visible rect, the rightmost optional column went first: \(shown(outline))")
        _ = at(560)
        verdict(essentialsVisible(outline) && !shown(outline).contains("kind") && !shown(outline).contains("owner"),
                "560: both optional columns went, essentials still inside: \(shown(outline))")
        _ = at(900)
        verdict(essentialsVisible(outline) && shown(outline).contains("kind"), "900: the leftmost hidden one came back first: \(shown(outline))")
        _ = at(1100)
        verdict(shown(outline) == ["name", "cpu", "mem", "kind", "owner"] && essentialsVisible(outline), "1100 again: every column is back: \(shown(outline))")
        // the header's menu still lists them, hidden or not
        let menu = outline.headerView?.menu
        menu?.delegate?.menuNeedsUpdate?(menu!)
        let titles = menu?.items.map(\.title) ?? []
        _ = at(560)
        menu?.delegate?.menuNeedsUpdate?(menu!)
        let states = menu?.items.map { "\($0.title)=\($0.state == .on ? "on" : "off")" } ?? []
        verdict(titles.contains("Kind") && titles.contains("Owner") && states.contains("Kind=off") && states.contains("Owner=off"),
                "the header menu lists an optional column that room hid, unchecked: \(states)")
        // a person hides one from the menu: it stays hidden through narrowing and widening
        _ = at(1100)
        if let kind = menu?.items.first(where: { $0.title == "Kind" }) { _ = kind.target?.perform(kind.action, with: kind) }
        _ = settle(); spin(0.2)
        verdict(!shown(outline).contains("kind"), "a person hides Kind from the menu: \(shown(outline))")
        _ = at(560); _ = at(1100)
        verdict(!shown(outline).contains("kind") && shown(outline).contains("owner"), "a person's choice is kept when there is room again: \(shown(outline))")
        // and shows it again
        menu?.delegate?.menuNeedsUpdate?(menu!)
        if let kind = menu?.items.first(where: { $0.title == "Kind" }) { _ = kind.target?.perform(kind.action, with: kind) }
        _ = settle(); spin(0.2)
        verdict(shown(outline).contains("kind"), "and shows it again: \(shown(outline))")
        UserDefaults.standard.removeObject(forKey: "OutlineTable.\(autosave).hiddenByPerson")
        window.contentViewController = nil; window.close()
        return ok ? 0 : 1
    }
}
