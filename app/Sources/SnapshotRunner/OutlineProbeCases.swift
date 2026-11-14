import AppKit
import Foundation
import SwiftUI
import UIComponents

/// A2: the cases specific to the wrapper, each in its own process and counted the same way.
extension ProbeChecks {

    static func sortedDeep(_ rows: [ProbeRow]) -> [ProbeRow] {
        rows.sorted { $0.mem > $1.mem }.map { row in
            var copy = row
            if let children = row.children { copy.children = sortedDeep(children) }
            return copy
        }
    }

    static func a2(_ name: String, _ options: ProbeOptions) -> Int32 {
        switch name {
        case "valuesAndAdd": return valuesAndAdd(options)
        case "closedGroupAdd": return closedGroupAdd(options)
        case "threeLevel": return threeLevel(options)
        case "bigLevel": return bigLevel(options)
        case "sectionHeaders": return sectionHeaders(options)
        case "callback": return callback(options)
        case "env": return environmentCase(options)
        case "menu": return menu(options)
        case "lines": return lines(options)
        case "tickBigGroup": return tickBigGroup(options)
        case "openWithInsert": return openWithInsert(options)
        case _ where name.hasPrefix("rv-"): return ProbeReviewed.run(String(name.dropFirst(3)), options)
        default:
            FileHandle.standardError.write(Data("unknown a2 case \(name)\n".utf8))
            return 2
        }
    }

    private static func timed(_ name: String, _ body: () -> Void) -> Double {
        mark("begin \(name)")
        body()
        let milliseconds = settle()
        spin(0.4)
        mark("end \(name)")
        return milliseconds
    }

    private static func valuesAndAdd(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: options.parents, kids: options.kids))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        model.expanded = Set(model.parentIDs.prefix(3))
        _ = settle(); spin(0.3)
        let rowsBefore = harness.outline.numberOfRows
        let ms = timed("valuesAndAdd") {
            var rows = model.rows
            ProbeActions.bumpValues(&rows)
            rows[0].children?.append(ProbeRow(id: model.newID(), name: "added", cpu: 1, mem: 1, kind: "Process"))
            model.rows = rows
        }
        say("valuesAndAdd rows=\(rowsBefore)->\(harness.outline.numberOfRows) expected=\(rowsBefore + 1) settleMs=\(Int(ms))")
        return harness.outline.numberOfRows == rowsBefore + 1 ? 0 : 1
    }

    private static func closedGroupAdd(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: options.parents, kids: options.kids))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        let outline = harness.outline!
        let rowsClosed = outline.numberOfRows
        _ = timed("closedGroupAdd") {
            for index in 0..<3 {
                model.rows[0].children?.append(ProbeRow(id: model.newID(), name: "added \(index)", cpu: 1, mem: 1, kind: "Process"))
            }
        }
        let stillClosed = outline.numberOfRows
        _ = timed("closedGroupOpen") { outline.expandItem(outline.item(atRow: 0)) }
        let expected = rowsClosed + options.kids + 3
        say("closedGroupOpened rows=\(outline.numberOfRows) expected=\(expected) whileClosed=\(stillClosed)")
        return outline.numberOfRows == expected && stillClosed == rowsClosed ? 0 : 1
    }

    private static func threeLevel(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 30, kids: 4, levels: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        model.expanded = ProbeActions.expandableIDs(model.rows)
        _ = settle(); spin(0.3)
        let rows = harness.outline.numberOfRows
        let ms = timed("threeLevelResort") {
            model.rows = sortedDeep(model.rows)
            model.sortOrder = [KeyPathComparator(\.mem, order: .reverse)]
        }
        say("threeLevelResort rows=\(rows)->\(harness.outline.numberOfRows) settleMs=\(Int(ms))")
        return harness.outline.numberOfRows == rows ? 0 : 1
    }

    private static func bigLevel(_ options: ProbeOptions) -> Int32 {
        var parent = makeProbeRows(parents: 1, kids: 6000)[0]
        parent.name = "Parent"
        let model = ProbeModel(rows: [parent])
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        model.expanded = [parent.id]
        _ = settle(); spin(0.3)
        let rows = harness.outline.numberOfRows
        let ms = timed("bigLevelResort") {
            model.rows[0].children?.sort { $0.mem > $1.mem }
            model.sortOrder = [KeyPathComparator(\.mem, order: .reverse)]
        }
        // a hosted cell has no text field to read the name from: the order is checked for text cells only
        let first = options.hosted ? "-" : ProbeChecks.name(harness.outline, row: 1)
        let expectedFirst = options.hosted ? "-" : (model.rows[0].children?.first?.name ?? "?")
        say("bigLevelResort rows=\(rows)->\(harness.outline.numberOfRows) settleMs=\(Int(ms)) firstChild=\(first) expected=\(expectedFirst)")
        return harness.outline.numberOfRows == rows && first == expectedFirst ? 0 : 1
    }

    private static func sectionHeaders(_ options: ProbeOptions) -> Int32 {
        var next = 0
        func id() -> Int { next += 1; return next }
        let days = (1...20).map { day in
            ProbeRow(id: id(), name: "Day \(day)", cpu: 0, mem: 0, kind: "", children: (1...10).map { _ in
                let rowID = id()
                return ProbeRow(id: rowID, name: "run \(rowID)", cpu: 0, mem: rowID, kind: "")
            }, headerTitle: "Day \(day)")
        }
        let model = ProbeModel(rows: days)
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, headers: true))
        let outline = harness.outline!
        let collapsed = outline.numberOfRows
        var counts: [Int] = [collapsed]
        _ = timed("headersOpen") { model.expanded = Set(days.map(\.id)) }
        counts.append(outline.numberOfRows)
        _ = timed("headersClose") { model.expanded = [] }
        counts.append(outline.numberOfRows)
        _ = timed("headersOpenAgain") { model.expanded = Set(days.map(\.id)) }
        counts.append(outline.numberOfRows)
        let selectable = !(outline.delegate?.outlineView?(outline, shouldSelectItem: outline.item(atRow: 0)!) ?? true)
        say("sectionHeaders rows closed/open/closed/open=\(counts) expected=[20, 220, 20, 220] headerNotSelectable=\(selectable)")
        return counts == [20, 220, 20, 220] && selectable ? 0 : 1
    }

    @MainActor
    private final class CallbackState {
        var armed = false
        var fired = false
        var rowsInside = -1
        var outline: NSOutlineView?
        var window: NSWindow?
    }

    /// A model change made from inside AppKit's own call into the table (the
    /// text closure runs while AppKit is asking for a cell), forced into the
    /// representable synchronously. The update must wait for the next turn.
    private static func callback(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 40, kids: 3))
        let state = CallbackState()
        let screen = ProbeScreen(model: model, hosted: false, onFirstColumnText: { row in
            guard state.armed, !state.fired else { return }
            state.fired = true
            // the caller's state changes and SwiftUI is told to update NOW, from inside AppKit's call
            model.rows.insert(ProbeRow(id: model.newID(), name: "inserted in callback", cpu: 0, mem: 0, kind: "x"), at: 0)
            state.window?.contentView?.layoutSubtreeIfNeeded()
            state.window?.contentView?.displayIfNeeded()
            state.rowsInside = state.outline?.numberOfRows ?? -1
        })
        let harness = ProbeHarness(screen)
        state.outline = harness.outline
        state.window = harness.window
        let before = harness.outline.numberOfRows
        mark("begin callback")
        state.armed = true
        harness.outline.reloadData(forRowIndexes: IndexSet(integer: 1), columnIndexes: IndexSet(integer: 0))
        _ = settle(); spin(0.4)
        mark("end callback")
        let after = harness.outline.numberOfRows
        let applied = state.rowsInside != before && state.rowsInside != -1
        say("callback fired=\(state.fired) rowsBefore=\(before) rowsInsideCallback=\(state.rowsInside) rowsAfter=\(after) appliedInCallback=\(applied ? 1 : 0)")
        return state.fired && after == before + 1 && !applied ? 0 : 1
    }

    private static func environmentCase(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3))
        let object = ProbeEnvObject()
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: true, readsEnvironment: true)
            .environment(object).controlSize(.small))
        _ = settle(); spin(0.3)
        _ = harness.outline
        object.value = 7
        model.rows[0].name = "changed"
        _ = settle(); spin(0.3)
        say("envCell controlSize=\(ProbeRecorder.controlSizes.sorted()) objectValues=\(ProbeRecorder.objectValues.sorted()) rowSizeStyle=\(harness.outline.rowSizeStyle.rawValue)")
        // small -> .small (rawValue 1); the cell must have seen "small" and never the default
        return ProbeRecorder.controlSizes == ["small"] && ProbeRecorder.objectValues.contains(42) && harness.outline.rowSizeStyle == .small ? 0 : 1
    }

    private static func menu(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, showsMenu: true))
        let outline = harness.outline!
        let window = harness.window
        func rightClick(row: Int) -> NSMenu? {
            let rect = outline.rect(ofRow: row)
            let inWindow = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: inWindow, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: 1) else { return nil }
            return outline.menu(for: event)
        }
        let one = rightClick(row: 2)
        outline.selectRowIndexes(IndexSet([4, 5, 6]), byExtendingSelection: false)
        _ = settle(); spin(0.2)
        let three = rightClick(row: 5)
        let outside = rightClick(row: 9)
        func titles(_ menu: NSMenu?) -> [String] { menu?.items.map(\.title) ?? [] }
        say("menu clickedOutsideEmptySelection=\(titles(one)) insideSelectionOf3=\(titles(three)) outsideSelectionOf3=\(titles(outside)) class=\(one.map { String(describing: type(of: $0)) } ?? "nil")")
        let ok = titles(one) == ["Act on 1"] && titles(three) == ["Act on 3"] && titles(outside) == ["Act on 1"]
        return ok ? 0 : 1
    }
}

extension ProbeChecks {
    /// A column that declares lines: those rows are taller by the system font's
    /// line, the others stay the standard height, and nothing warns.
    fileprivate static func lines(_ options: ProbeOptions) -> Int32 {
        let model = ProbeModel(rows: makeProbeRows(parents: 10, kids: 2))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, twoLineRows: true))
        let outline = harness.outline!
        model.expanded = Set(model.parentIDs)
        _ = settle(); spin(0.3)
        let standard = outline.rowHeight
        var tall: [CGFloat] = [], plain: [CGFloat] = []
        mark("begin lines")
        for row in 0..<outline.numberOfRows {
            let id = model.rows.flatMap { [$0] + ($0.children ?? []) }.first { ProbeChecks.name(outline, row: row) == $0.name }?.id ?? 0
            if id % 2 == 0 { tall.append(outline.rect(ofRow: row).height) } else { plain.append(outline.rect(ofRow: row).height) }
        }
        mark("end lines")
        let ok = !tall.isEmpty && !plain.isEmpty && plain.allSatisfy { $0 == standard } && tall.allSatisfy { $0 > standard }
        say("lines standard=\(standard) tallRows=\(Set(tall).sorted()) plainRows=\(Set(plain).sorted())")
        return ok ? 0 : 1
    }
}

extension ProbeChecks {
    /// The state in which opening ONE group warned on SwiftUI's `Table` in the
    /// field: about 655 closed top-level rows with no children in the data, ONE
    /// group opened per update with its children inserted in that same update,
    /// and a values-only update of every row one main-loop turn later. Four
    /// groups near the top, then the middle one, then the last.
    fileprivate static func openWithInsert(_ options: ProbeOptions) -> Int32 {
        var rows = makeProbeRows(parents: 655, kids: 1)
        for index in rows.indices { rows[index].children = [] }          // closed and empty: the children are not in the data yet
        let model = ProbeModel(rows: rows)
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        var values = model.rows
        ProbeActions.bumpValues(&values)
        model.rows = values                                                // the values-only first load
        _ = settle(); spin(0.3)
        let targets = [0, 1, 2, 3, model.rows.count / 2, model.rows.count - 1]
        mark("begin openWithInsert")
        for index in targets {
            let id = model.rows[index].id
            model.rows[index].children = (1...8).map { k in
                ProbeRow(id: model.newID(), name: "inserted \(k)", cpu: 1, mem: k, kind: "Process")
            }
            model.expanded.insert(id)                                      // one update: the children AND the open
            spin(0.05)                                                     // one main-loop turn later
            var refreshed = model.rows
            ProbeActions.bumpValues(&refreshed)
            model.rows = refreshed
            spin(0.3)
        }
        _ = settle(); spin(0.4)
        mark("end openWithInsert")
        let expected = 655 + targets.count * 8
        say("openWithInsert rows=\(harness.outline.numberOfRows) expected=\(expected) opened=\(targets.count)")
        return harness.outline.numberOfRows == expected ? 0 : 1
    }
}

extension ProbeChecks {
    /// A tick on a group of 1,000 members is delivered at once (not a turn later) and brings no
    /// reentrancy warning back: the deferral of writes exists for writes made inside AppKit's own
    /// callbacks, and a box's action is not one.
    fileprivate static func tickBigGroup(_ options: ProbeOptions) -> Int32 {
        let model = TickModel.big(1000)
        let harness = ProbeHarness(TickScreen(model: model, hosted: options.hosted))
        let outline = harness.outline!
        model.expanded = ["big"]
        _ = settle(); spin(0.3)
        var ok = true
        func verdict(_ good: Bool, _ line: String) { say((good ? "PASS " : "FAIL ") + line); if !good { ok = false } }
        mark("begin tickBigGroup")
        func send(_ row: Int) {
            guard let box = tickButton(outline, row: row), let action = box.action else { return }
            box.state = box.state == .on ? .off : .on
            _ = NSApp.sendAction(action, to: box.target, from: box)
        }
        // the group's box: 1,000 members, delivered by the action itself, before any run loop turn
        send(0)
        verdict(model.ticked.count == 1000 && model.setCalls == ["big=true"], "group of 1,000 ticked at once: ticked=\(model.ticked.count) setCalls=\(model.setCalls)")
        _ = settle(); spin(0.3)
        verdict(word(model.state(model.rows[0])) == "on", "the group's box after the update: \(word(model.state(model.rows[0])))")
        send(0)
        verdict(model.ticked.isEmpty, "unticked at once: ticked=\(model.ticked.count)")
        send(0); _ = settle(); spin(0.2)
        send(2)                                                         // one member (row 0 is the group, 1 the first member)
        _ = settle(); spin(0.3)
        verdict(model.ticked.count == 999 && word(model.state(model.rows[0])) == "mixed", "one member off: ticked=\(model.ticked.count), group \(word(model.state(model.rows[0])))")
        mark("end tickBigGroup")
        return ok ? 0 : 1
    }
}
