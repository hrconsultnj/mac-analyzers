import AppKit
import Foundation
import SwiftUI
import UIComponents

/// A1 and A3: the thirteen actions of the measurement, and the 120 s soak.
@MainActor
enum ProbeActions {

    static let needsOpen: Set<String> = ["addChild", "removeChild", "collapse1"]

    static func expandableIDs(_ rows: [ProbeRow]) -> Set<Int> {
        var ids = Set<Int>()
        func visit(_ row: ProbeRow) {
            guard let children = row.children, !children.isEmpty else { return }
            ids.insert(row.id)
            children.forEach(visit)
        }
        rows.forEach(visit)
        return ids
    }

    static func bumpValues(_ rows: inout [ProbeRow]) {
        for index in rows.indices {
            rows[index].cpu += 0.1
            rows[index].mem += 1
            if var children = rows[index].children {
                bumpValues(&children)
                rows[index].children = children
            }
        }
    }

    static func perform(_ name: String, model: ProbeModel, outline: NSOutlineView) {
        switch name {
        case "expand1":
            if outline.numberOfRows > 0 { outline.expandItem(outline.item(atRow: 0)) }
        case "collapse1":
            if outline.numberOfRows > 0 { outline.collapseItem(outline.item(atRow: 0)) }
        case "expandAll":
            model.expanded = expandableIDs(model.rows)
        case "expandHalf":
            model.expanded = Set(ProbeActions.expandableIDs(model.rows).sorted().enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        case "expandAllOption":
            outline.expandItem(nil, expandChildren: true)
        case "values":
            var rows = model.rows
            bumpValues(&rows)
            model.rows = rows
        case "addChild":
            guard !model.rows.isEmpty else { return }
            model.rows[0].children?.append(ProbeRow(id: model.newID(), name: "new proc", cpu: 1, mem: 5, kind: "Process"))
        case "removeChild":
            guard !model.rows.isEmpty else { return }
            _ = model.rows[0].children?.popLast()
        case "addParent":
            model.rows.insert(ProbeRow(id: model.newID(), name: "Parent new", cpu: 1, mem: 5, kind: "App",
                                       children: [ProbeRow(id: model.newID(), name: "proc n", cpu: 1, mem: 1, kind: "Process")]),
                              at: 0)
        case "removeParent":
            if !model.rows.isEmpty { model.rows.removeFirst() }
        case "resort":
            model.rows.sort { $0.mem > $1.mem }
            model.sortOrder = [KeyPathComparator(\.mem, order: .reverse)]
        case "filter10":
            model.rows = Array(model.all.prefix(10))
        case "filterBack":
            model.rows = model.all
        case "select":
            if outline.numberOfRows > 2 { outline.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false) }
        default:
            FileHandle.standardError.write(Data("unknown action \(name)\n".utf8))
            exit(2)
        }
    }

    /// Row heights the outline settled on, for text and hosted cells.
    static func info(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 5, kids: 2))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        let outline = harness.outline!
        model.expanded = Set(model.parentIDs)
        _ = settle(); spin(0.3)
        let heights = (0..<min(4, outline.numberOfRows)).map { Int(outline.rect(ofRow: $0).height) }
        say("info hosted=\(options.hosted) rowHeight=\(outline.rowHeight) rowSizeStyle=\(outline.rowSizeStyle.rawValue) automatic=\(outline.usesAutomaticRowHeights) rowRectHeights=\(heights) header=\(outline.headerView?.frame.height ?? 0) intercell=\(outline.intercellSpacing.height)")
        return 0
    }

    static func single(_ name: String, _ options: ProbeOptions) -> Int32 {
        if name == "info" { return info(options) }
        let model = ProbeModel(rows: makeProbeRows(parents: options.parents, kids: options.kids, levels: options.levels))
        if name == "appear" { mark("begin appear") }
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        guard let outline = harness.outline else { say("FAIL no outline view found"); return 1 }
        if name == "appear" {
            spin(0.4)
            mark("end appear")
            say("action=appear settleMs=\(Int(harness.appearMilliseconds)) rows=\(outline.numberOfRows)")
            return 0
        }
        if needsOpen.contains(name) {
            model.expanded = Set(model.parentIDs.prefix(3))
            _ = settle(); spin(0.3)
        }
        mark("begin \(name)")
        perform(name, model: model, outline: outline)
        let milliseconds = settle()
        spin(0.4)
        mark("end \(name)")
        say("action=\(name) settleMs=\(Int(milliseconds)) rows=\(outline.numberOfRows)")
        return 0
    }

    /// A3: values every second; every 5 s add or remove a child; every 17 s a
    /// parent; every 29 s a re-sort; every 41 s a filter and back; every 11 s a
    /// selection; every 23 s close then open one group. Three groups open.
    static func soak(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: options.parents, kids: options.kids, levels: options.levels))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        guard let outline = harness.outline else { say("FAIL no outline view found"); return 1 }
        model.expanded = Set(model.parentIDs.prefix(3))
        _ = settle(); spin(0.5)
        mark("begin soak")
        for t in 0..<options.seconds {
            perform("values", model: model, outline: outline)
            if t % 5 == 1 { perform("addChild", model: model, outline: outline) }
            if t % 5 == 3 { perform("removeChild", model: model, outline: outline) }
            if t % 17 == 7 { perform("addParent", model: model, outline: outline) }
            if t % 17 == 12 { perform("removeParent", model: model, outline: outline) }
            if t % 29 == 20 { perform("resort", model: model, outline: outline) }
            if t % 41 == 30 { perform("filter10", model: model, outline: outline) }
            if t % 41 == 33 { perform("filterBack", model: model, outline: outline) }
            if t % 11 == 5 { perform("select", model: model, outline: outline) }
            if t % 23 == 9 { perform("collapse1", model: model, outline: outline) }
            if t % 23 == 11 { perform("expand1", model: model, outline: outline) }
            spin(1.0)
        }
        mark("end soak")
        say("soak seconds=\(options.seconds) rows=\(outline.numberOfRows)")
        return 0
    }
}
