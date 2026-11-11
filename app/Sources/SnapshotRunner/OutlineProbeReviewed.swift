import AppKit
import Foundation
import SwiftUI
import UIComponents

/// The independent review's cases (`a2:rv-<name>`), kept as shipped probes: each compares what
/// AppKit shows, row by row, with the model flattened through the expanded set, after updates
/// that go through the paths the other probes do not check end to end. Three more
/// (`closedDeep`, `closedUnderHeader`, `closedExpandAllSameUpdate`) cover the closed-group cases.
@MainActor
enum ProbeReviewed {
    static func run(_ name: String, _ options: ProbeOptions) -> Int32 {
        switch name {
        case "order": return order(options)
        case "reparent": return reparent(options)
        case "closedAfterOpen": return closedAfterOpen(options)
        case "grand": return grand(options)
        case "bulkRemove": return bulkRemove(options)
        case "bulkChild": return bulkChild(options)
        case "bulkSelectMoved": return bulkSelectMoved(options)
        case "nilEmpty": return nilEmpty(options)
        case "dup": return dup(options)
        case "linesOffscreen": return linesOffscreen(options)
        case "closedDeep": return closedDeep(options)
        case "closedUnderHeader": return closedUnderHeader(options)
        case "closedExpandAllSameUpdate": return closedExpandAllSameUpdate(options)
        default: say("unknown \(name)"); return 2
        }
    }

    // MARK: helpers

    static func expected(_ rows: [ProbeRow], _ open: Set<Int>) -> [String] {
        var out: [String] = []
        func walk(_ rows: [ProbeRow]) {
            for row in rows {
                out.append(row.name)
                if let kids = row.children, !kids.isEmpty, open.contains(row.id) { walk(kids) }
            }
        }
        walk(rows)
        return out
    }

    static func shown(_ outline: NSOutlineView) -> [String] {
        (0..<outline.numberOfRows).map { row in
            (outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue ?? "?"
        }
    }

    static func compare(_ label: String, _ outline: NSOutlineView, _ model: ProbeModel, open: Set<Int>? = nil) -> Bool {
        let want = expected(model.rows, open ?? model.expanded)
        let got = shown(outline)
        let ok = want == got
        var detail = ""
        if !ok {
            let firstDiff = zip(want, got).enumerated().first { $0.element.0 != $0.element.1 }
            detail = " rows want=\(want.count) got=\(got.count) firstDiff=\(firstDiff.map { "#\($0.offset) want \($0.element.0) got \($0.element.1)" } ?? "length only")"
        }
        say("\(ok ? "PASS" : "FAIL") \(label)\(detail)")
        return ok
    }

    static func step(_ label: String, _ body: () -> Void) {
        mark("begin \(label)")
        body()
        _ = settle(); spin(0.3)
        mark("end \(label)")
    }

    static func sortDeep(_ rows: [ProbeRow], by: (ProbeRow, ProbeRow) -> Bool) -> [ProbeRow] {
        rows.sorted(by: by).map { row in
            var copy = row
            if let kids = row.children { copy.children = sortDeep(kids, by: by) }
            return copy
        }
    }

    // MARK: cases

    /// A re-sort below the bulk limit: every level moves by moveItem. Is the order AppKit shows the model's?
    static func order(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 200, kids: 5))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        model.expanded = Set(model.parentIDs.enumerated().filter { $0.offset % 3 == 0 }.map(\.element))
        _ = settle(); spin(0.3)
        var ok = compare("order initial", harness.outline, model)
        step("resort mem desc") { model.rows = sortDeep(model.rows) { ($0.mem, $0.id) > ($1.mem, $1.id) } }
        ok = compare("order after re-sort by memory (moves)", harness.outline, model) && ok
        step("resort name") { model.rows = sortDeep(model.rows) { $0.name < $1.name } }
        ok = compare("order after re-sort by name (moves)", harness.outline, model) && ok
        step("shuffle") {
            var g = SystemRandomNumberGenerator()
            var rows = model.rows.shuffled(using: &g)
            for i in rows.indices { rows[i].children?.shuffle(using: &g) }
            model.rows = rows
        }
        ok = compare("order after a shuffle of every level (moves)", harness.outline, model) && ok
        return ok ? 0 : 1
    }

    /// Ids that change parent AND position in one update, with the order changing too.
    static func reparent(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 40, kids: 5))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        model.expanded = Set(model.parentIDs.prefix(10))      // 0..9 open, the rest closed
        _ = settle(); spin(0.3)
        step("reparent") {
            var rows = model.rows
            // open 0 -> open 5 (to the front), closed 20 -> open 1 (to the end), open 2 -> closed 30
            let a = rows[0].children!.removeLast()
            rows[5].children!.insert(a, at: 0)
            let b = rows[20].children!.removeFirst()
            rows[1].children!.append(b)
            let c = rows[2].children!.removeFirst()
            rows[30].children!.insert(c, at: 2)
            // and a parent removed whose children moved elsewhere: parent 3's children go to parent 4
            let orphans = rows[3].children!
            rows.remove(at: 3)
            rows[3].children!.append(contentsOf: orphans)              // index 3 is now old parent 4
            rows.swapAt(6, 7)
            model.rows = rows
        }
        var ok = compare("reparent (open parents)", harness.outline, model)
        step("open the closed ones") { model.expanded = Set(model.rows.map(\.id)) }
        ok = compare("reparent after opening everything", harness.outline, model) && ok
        return ok ? 0 : 1
    }

    /// A group opened, then closed (AppKit has its children), then its children change while it is closed.
    static func closedAfterOpen(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 50, kids: 5))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        let target = model.rows[3].id
        step("open") { model.expanded = [target] }
        step("close") { model.expanded = [] }
        step("replace children while closed") {
            var rows = model.rows
            rows[3].children = (0..<3).map { ProbeRow(id: model.newID(), name: "new \($0)", cpu: 1, mem: 1, kind: "Process") }
            model.rows = rows
        }
        step("reopen") { model.expanded = [target] }
        return compare("closed group whose children were replaced, reopened", harness.outline, model) ? 0 : 1
    }

    /// A closed group gains a NEW child that has children, and an existing child gains one; then Expand All
    /// in the same update, and then nothing else happens.
    static func grand(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3, levels: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        step("grow while closed, then expand all in the same update") {
            var rows = model.rows
            let grandKids = (0..<2).map { ProbeRow(id: model.newID(), name: "new grandchild \($0)", cpu: 1, mem: 1, kind: "Process") }
            rows[0].children!.append(ProbeRow(id: model.newID(), name: "new child", cpu: 1, mem: 1, kind: "App", children: grandKids))
            rows[0].children![0].children!.append(ProbeRow(id: model.newID(), name: "added to existing child", cpu: 1, mem: 1, kind: "Process"))
            model.rows = rows
            model.expanded = ProbeActions.expandableIDs(rows)
        }
        var ok = compare("grand: right after (no later update)", harness.outline, model)
        step("grow while closed, separate updates") {
            var rows = model.rows
            rows[5].children![1].children!.append(ProbeRow(id: model.newID(), name: "added under closed", cpu: 1, mem: 1, kind: "Process"))
            model.rows = rows
        }
        ok = compare("grand: after a later update", harness.outline, model) && ok
        // the same, starting closed and opening with a separate update
        let model2 = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3, levels: 3))
        let harness2 = ProbeHarness(ProbeScreen(model: model2, hosted: false))
        step("grow while closed") {
            var rows = model2.rows
            let grandKids = (0..<2).map { ProbeRow(id: model2.newID(), name: "B grandchild \($0)", cpu: 1, mem: 1, kind: "Process") }
            rows[0].children!.append(ProbeRow(id: model2.newID(), name: "B child", cpu: 1, mem: 1, kind: "App", children: grandKids))
            model2.rows = rows
        }
        step("expand all later") { model2.expanded = ProbeActions.expandableIDs(model2.rows) }
        ok = compare("grand: expand all in a later update", harness2.outline, model2) && ok
        return ok ? 0 : 1
    }

    /// More than 1,500 moves at the root AND removals: the bulk path with nodes that go away.
    static func bulkRemove(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 3000, kids: 2))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        model.expanded = Set(model.parentIDs.prefix(40))
        model.selection = [model.rows[10].children![1].id]
        _ = settle(); spin(0.3)
        step("reverse and remove 25") {
            var rows = Array(model.rows.reversed())
            rows.removeSubrange(100..<125)
            model.rows = rows
        }
        var ok = compare("bulk root with removals", harness.outline, model)
        step("open all") { model.expanded = Set(model.rows.map(\.id)) }
        ok = compare("bulk root with removals, then open all", harness.outline, model) && ok
        say("selection after: \(model.selection.sorted()) selectedRows=\(harness.outline.selectedRowIndexes.count)")
        return ok ? 0 : 1
    }

    /// The bulk path one level down: an open group of 3,000 children reversed with removals,
    /// with open groups nested under it.
    static func bulkChild(_ options: ProbeOptions) -> Int32 {
        var top = makeProbeRows(parents: 1, kids: 3000, levels: 2)
        // nest: give the first 20 children their own children
        var next = 50_000_000
        for i in 0..<20 {
            next += 1
            top[0].children![i].children = [ProbeRow(id: next, name: "nested \(next)", cpu: 1, mem: 1, kind: "Process")]
        }
        let model = ProbeModel(rows: top)
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        model.expanded = Set([top[0].id] + top[0].children!.prefix(20).map(\.id))
        model.selection = [top[0].children![5].id]
        _ = settle(); spin(0.3)
        step("reverse children and remove 30") {
            var rows = model.rows
            var kids = Array(rows[0].children!.reversed())
            kids.removeSubrange(500..<530)
            rows[0].children = kids
            model.rows = rows
        }
        let ok = compare("bulk child level with nested open groups and removals", harness.outline, model)
        let selected = harness.outline.selectedRow
        let selectedName = selected >= 0 ? ((harness.outline.view(atColumn: 0, row: selected, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue ?? "?") : "none"
        say("selection after: model=\(model.selection.sorted()) shown=\(selectedName)")
        return ok ? 0 : 1
    }

    /// Bulk at the root while the selected row moves to another parent.
    static func bulkSelectMoved(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 3000, kids: 2))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        model.expanded = Set(model.parentIDs.prefix(40))
        let moving = model.rows[2].children![0]
        model.selection = [moving.id]
        _ = settle(); spin(0.3)
        step("reverse and move the selected child to another open parent") {
            var rows = model.rows
            rows[2].children!.removeFirst()
            rows[30].children!.append(moving)
            model.rows = Array(rows.reversed())
        }
        let ok = compare("bulk root, selected child moved parent", harness.outline, model)
        let selected = harness.outline.selectedRow
        let selectedName = selected >= 0 ? ((harness.outline.view(atColumn: 0, row: selected, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue ?? "?") : "none"
        say("selection after: model=\(model.selection.sorted()) shown=\(selectedName) want=\(moving.name)")
        return ok && selectedName == moving.name ? 0 : 1
    }

    /// children nil -> [] -> [x] -> nil, while the row is in the expanded set.
    static func nilEmpty(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 10, kids: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        let id = model.rows[2].id
        model.expanded = [id]
        _ = settle(); spin(0.3)
        var ok = true
        for (label, kids) in [("nil", nil), ("empty", []), ("two", [ProbeRow(id: 900, name: "x900", cpu: 1, mem: 1, kind: "P"), ProbeRow(id: 901, name: "x901", cpu: 1, mem: 1, kind: "P")]), ("nil again", nil), ("one", [ProbeRow(id: 902, name: "x902", cpu: 1, mem: 1, kind: "P")])] as [(String, [ProbeRow]?)] {
            step("children \(label)") { model.rows[2].children = kids }
            let item = harness.outline.item(atRow: 2)
            ok = compare("children \(label) (expandable=\(harness.outline.isExpandable(item)) open=\(harness.outline.isItemExpanded(item)))", harness.outline, model) && ok
        }
        return ok ? 0 : 1
    }

    /// The same id twice: in two parents, and at the root and under a parent.
    static func dup(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 10, kids: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        model.expanded = Set(model.parentIDs)
        _ = settle(); spin(0.3)
        step("duplicate") {
            var rows = model.rows
            rows[4].children!.append(rows[1].children![0])        // same id in two parents
            rows.append(rows[0].children![1])                    // same id at the root
            model.rows = rows
        }
        say("dup rows shown=\(harness.outline.numberOfRows) (model with duplicates counted once each would be \(expected(model.rows, model.expanded).count - 2))")
        step("remove the duplicates again") {
            var rows = model.rows
            rows[4].children!.removeLast()
            rows.removeLast()
            model.rows = rows
        }
        return compare("after duplicates are removed again", harness.outline, model) ? 0 : 1
    }

    /// A two-line row whose line count changes while it is off screen.
    static func linesOffscreen(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 300, kids: 0, levels: 1))
        let screen = ProbeScreen(model: model, hosted: false, twoLineRows: true)
        let harness = ProbeHarness(screen)
        let outline = harness.outline!
        _ = settle(); spin(0.3)
        // row 280 is far below; its id is odd -> one line. Make its id-parity rule flip by swapping ids is not possible,
        // so change which rows are even by replacing row 281 (odd id) with an even-id row of the same name.
        let before = outline.rect(ofRow: 280).height
        step("values-only update that changes a far row's line count") {
            var rows = model.rows
            let old = rows[280]
            rows[280] = ProbeRow(id: old.id, name: old.name, cpu: old.cpu + 1, mem: old.mem, kind: "Two")
            model.rows = rows
        }
        let mid = outline.rect(ofRow: 280).height
        step("scroll it into view") { outline.scrollRowToVisible(280) }
        say("after scrolling it into view: height=\(outline.rect(ofRow: 280).height) (right after the update: \(mid))")
        say("row 280 height before=\(before) after=\(outline.rect(ofRow: 280).height) (kind changed to Two while off screen: want taller)")
        return outline.rect(ofRow: 280).height > before ? 0 : 1
    }

    // MARK: closed groups, below the first level

    /// Four levels: a row deep inside closed groups gains a row, then Expand All in a LATER update.
    static func closedDeep(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 6, kids: 2, levels: 4))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        step("grow three levels down while everything is closed") {
            var rows = model.rows
            rows[0].children![0].children![0].children!.append(ProbeRow(id: model.newID(), name: "added at depth 4", cpu: 1, mem: 1, kind: "Process"))
            let grand = (0..<2).map { ProbeRow(id: model.newID(), name: "new deep \($0)", cpu: 1, mem: 1, kind: "Process") }
            rows[1].children![1].children!.append(ProbeRow(id: model.newID(), name: "new at depth 3 with children", cpu: 1, mem: 1, kind: "App", children: grand))
            model.rows = rows
        }
        step("expand all") { model.expanded = ProbeActions.expandableIDs(model.rows) }
        return compare("closed, four levels, then expand all", harness.outline, model) ? 0 : 1
    }

    /// The change and Expand All arrive in ONE update.
    static func closedExpandAllSameUpdate(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 8, kids: 3, levels: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false))
        step("a row added under a closed child, and expand all, in one update") {
            var rows = model.rows
            rows[2].children![1].children!.append(ProbeRow(id: model.newID(), name: "added under closed child", cpu: 1, mem: 1, kind: "Process"))
            rows[2].children!.append(ProbeRow(id: model.newID(), name: "new child with a child", cpu: 1, mem: 1, kind: "App",
                                              children: [ProbeRow(id: model.newID(), name: "its child", cpu: 1, mem: 1, kind: "Process")]))
            model.rows = rows
            model.expanded = ProbeActions.expandableIDs(rows)
        }
        return compare("closed change and expand all in one update", harness.outline, model) ? 0 : 1
    }

    /// Under a section header: header -> runs -> items; an item is added under a closed run, then everything opens.
    static func closedUnderHeader(_ options: ProbeOptions) -> Int32 {
        var next = 0
        func id() -> Int { next += 1; return next }
        let days = (1...4).map { day in
            ProbeRow(id: id(), name: "Day \(day)", cpu: 0, mem: 0, kind: "", children: (1...3).map { run in
                ProbeRow(id: id(), name: "run \(day).\(run)", cpu: 0, mem: 0, kind: "", children: (1...2).map { item in
                    ProbeRow(id: id(), name: "item \(day).\(run).\(item)", cpu: 0, mem: 0, kind: "")
                })
            }, headerTitle: "Day \(day)")
        }
        let model = ProbeModel(rows: days)
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, headers: true))
        let outline = harness.outline!
        step("an item under a closed run under a closed header, and a new run with items") {
            var rows = model.rows
            rows[0].children![1].children!.append(ProbeRow(id: model.newID(), name: "item added", cpu: 0, mem: 0, kind: ""))
            rows[0].children!.append(ProbeRow(id: model.newID(), name: "new run", cpu: 0, mem: 0, kind: "", children: [
                ProbeRow(id: model.newID(), name: "new run item", cpu: 0, mem: 0, kind: "")]))
            model.rows = rows
        }
        step("expand all") { model.expanded = ProbeActions.expandableIDs(model.rows) }
        // header rows have no first-column cell to read: compare the number of rows AppKit shows
        func count(_ rows: [ProbeRow]) -> Int {
            rows.reduce(0) { total, row in total + 1 + (row.children.map(count) ?? 0) }
        }
        let want = count(model.rows)
        say("\(outline.numberOfRows == want ? "PASS" : "FAIL") closed under a section header, then expand all: rows want=\(want) got=\(outline.numberOfRows)")
        return outline.numberOfRows == want ? 0 : 1
    }
}
