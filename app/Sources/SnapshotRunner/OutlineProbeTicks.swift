import AppKit
import Foundation
import Observation
import SwiftUI
import UIComponents

struct TickRow: Identifiable {
    let id: String
    var name: String
    var children: [TickRow]?
    var unavailable: String?
}

/// A review's tick semantics (section 1.5) on a fixture: a group is computed
/// over its choosable members, a click on a group sets every choosable member,
/// and the approved set sends a list that leaves out every row that cannot be chosen.
@MainActor
@Observable
final class TickModel {
    let rows: [TickRow] = [
        TickRow(id: "r1", name: "Locked file", unavailable: "In use"),
        TickRow(id: "g1", name: "Group one", children: [
            TickRow(id: "a", name: "a"), TickRow(id: "b", name: "b"), TickRow(id: "c", name: "c", unavailable: "Protected"),
        ]),
        TickRow(id: "g2", name: "Group two", children: [TickRow(id: "d", name: "d"), TickRow(id: "e", name: "e")]),
        TickRow(id: "x", name: "Single"),
        TickRow(id: "y", name: "Locked two", unavailable: "In use"),
    ]
    var ticked: Set<String> = []
    var expanded: Set<String> = []
    var selection: Set<String> = []
    var setCalls: [String] = []

    func leaves(_ row: TickRow) -> [TickRow] {
        guard let children = row.children else { return [row] }
        return children.flatMap(leaves)
    }

    func state(_ row: TickRow) -> OutlineTickState {
        if row.children == nil {
            if let reason = row.unavailable { return .unavailable(reason: reason) }
            return ticked.contains(row.id) ? .on : .off
        }
        return OutlineTickState.combining(row.children!.map(state), whenNoneChoosable: "Nothing here can be chosen")
    }

    func set(_ row: TickRow, _ value: Bool) {
        setCalls.append("\(row.id)=\(value)")
        for leaf in leaves(row) where leaf.unavailable == nil {
            if value { ticked.insert(leaf.id) } else { ticked.remove(leaf.id) }
        }
    }

    var approvable: Set<String> { Set(rows.flatMap(leaves).map(\.id)) }
    var unavailableIDs: Set<String> { Set(rows.flatMap(leaves).filter { $0.unavailable != nil }.map(\.id)) }
    var deselected: Set<String> { approvable.subtracting(ticked).union(unavailableIDs) }
    var isNarrowed: Bool { !deselected.isEmpty }
    var approved: Set<String> { approvable.subtracting(deselected) }
}

struct TickScreen: View {
    @Bindable var model: TickModel

    var body: some View {
        OutlineTable(model.rows, children: \.children, selection: $model.selection, expanded: $model.expanded,
                     autosave: "probe.ticks") {
            OutlineColumn("name", "Name", text: { $0.name })
        }
        .ticks(OutlineTicks(state: { model.state($0) }, set: { model.set($0, $1) }, label: { "Include \($0.name)" }))
        .rowEnabled { $0.unavailable == nil }
    }
}

extension ProbeChecks {

    static func checkbox(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let found = checkbox(in: sub) { return found } }
        return nil
    }

    static func tickButton(_ outline: NSOutlineView, row: Int) -> NSButton? {
        outline.view(atColumn: 0, row: row, makeIfNecessary: true).flatMap(checkbox(in:))
    }

    static func word(_ state: OutlineTickState) -> String {
        switch state {
        case .on: "on"
        case .off: "off"
        case .mixed: "mixed"
        case .unavailable: "unavailable"
        }
    }

    static func key(_ code: UInt16, _ characters: String, window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
    }

    /// A7.
    static func ticks() -> Int32 {
        var failed = false
        func verdict(_ ok: Bool, _ line: String) {
            say((ok ? "PASS " : "FAIL ") + line)
            if !ok { failed = true }
        }
        let model = TickModel()
        let harness = ProbeHarness(TickScreen(model: model))
        let outline = harness.outline!
        func box(_ row: Int) -> String {
            switch tickButton(outline, row: row)?.state {
            case .on: "on"
            case .mixed: "mixed"
            case .off: "off"
            default: "none"
            }
        }
        func groups() -> String { "g1=\(word(model.state(model.rows[1]))) g2=\(word(model.state(model.rows[2])))" }

        // tick all: the three rows that can be ticked at the top (the group rows and the single one)
        for row in [1, 2, 3] { tickButton(outline, row: row)?.performClick(nil) }
        _ = settle(); spin(0.2)
        verdict(model.ticked == ["a", "b", "d", "e", "x"] && [box(1), box(2), box(3)] == ["on", "on", "on"],
                "ticks tickAll ticked=\(model.ticked.sorted()) groups \(groups()) checkboxes g1,g2,x=\([box(1), box(2), box(3)]) (c, r1, y are not choosable and stay off)")

        // untick a group
        tickButton(outline, row: 2)?.performClick(nil)
        _ = settle(); spin(0.2)
        verdict(model.state(model.rows[2]) == .off && !model.ticked.contains("d") && box(2) == "off" && box(1) == "on",
                "ticks untickGroup groups \(groups()) checkboxes g1,g2=\([box(1), box(2)])")

        // one member of the group: the group is mixed
        model.expanded = ["g1", "g2"]
        _ = settle(); spin(0.2)
        // rows now: r1 g1 a b c g2 d e x y
        tickButton(outline, row: 6)?.performClick(nil)
        _ = settle(); spin(0.2)
        // rows now: r1 g1 a b c g2 d e x y — the group's box must follow a tick on a member
        verdict(model.state(model.rows[2]) == .mixed && box(5) == "mixed" && box(6) == "on" && box(1) == "on",
                "ticks oneMember groups \(groups()) checkboxes g1,g2,d=\([box(1), box(5), box(6)])")

        // Space on a selection that holds a row that cannot be chosen
        outline.selectRowIndexes(IndexSet([0, 8]), byExtendingSelection: false)       // r1 (locked) and x (ticked)
        harness.window.makeFirstResponder(outline)
        _ = settle(); spin(0.2)
        if let space = key(49, " ", window: harness.window) { outline.keyDown(with: space) }
        _ = settle(); spin(0.2)
        verdict(!model.ticked.contains("x") && !model.ticked.contains("r1"), "ticks spaceOnSelection ticked=\(model.ticked.sorted()) (x toggled, r1 skipped)")

        // click a tick that cannot be chosen
        let before = model.ticked
        let calls = model.setCalls.count
        let locked = tickButton(outline, row: 0)
        locked?.performClick(nil)
        if let locked, let action = locked.action { _ = NSApp.sendAction(action, to: locked.target, from: locked) }   // even when sent
        _ = settle(); spin(0.2)
        verdict(model.ticked == before && model.setCalls.count == calls && locked?.isEnabled == false,
                "ticks unavailableClick changed=\(model.ticked == before ? 0 : 1) setCalls=\(model.setCalls.count - calls) enabled=\(locked?.isEnabled ?? true) help=\(locked?.accessibilityHelp() ?? "nil")")

        verdict(model.approved.isDisjoint(with: model.unavailableIDs) && model.isNarrowed,
                "ticks approved contains unavailable=\(model.approved.intersection(model.unavailableIDs).count) isNarrowed=\(model.isNarrowed) approved=\(model.approved.sorted()) deselected=\(model.deselected.sorted())")
        return failed ? 1 : 0
    }

    // MARK: - A8

    private struct ColumnState: Equatable {
        var widths: [String: Int]
        var hidden: Set<String>
        var order: [String]
    }

    private static func columnState(_ outline: NSOutlineView) -> ColumnState {
        var widths: [String: Int] = [:]
        var hidden = Set<String>()
        for column in outline.tableColumns {
            widths[column.identifier.rawValue] = Int(column.width.rounded())
            if column.isHidden { hidden.insert(column.identifier.rawValue) }
        }
        return ColumnState(widths: widths, hidden: hidden, order: outline.tableColumns.map(\.identifier.rawValue))
    }

    static func autosave() -> Int32 {
        let name = "probe-autosave-\(getpid())"
        // (the process-wide cleanup in OutlineProbe.run removes what this saves)
        var saved: ColumnState?
        var titlesOK = false
        do {
            let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3))
            let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, autosave: name))
            let outline = harness.outline!
            outline.tableColumns[1].width = 133
            outline.tableColumns[2].isHidden = true
            outline.moveColumn(1, toColumn: 3)
            _ = settle(); spin(0.3)
            // an update after the person dragged a column: titles still follow the column, not its position
            model.rows[0].name = "renamed"
            _ = settle(); spin(0.3)
            let expected = ["name": "Name", "cpu": "CPU", "mem": "Memory", "kind": "Kind"]
            titlesOK = outline.tableColumns.allSatisfy { expected[$0.identifier.rawValue] == $0.title }
            saved = columnState(outline)
            harness.window.contentViewController = nil
            harness.window.close()
        }
        spin(0.3)
        let model = ProbeModel(rows: makeProbeRows(parents: 20, kids: 3))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: false, autosave: name))
        let restored = columnState(harness.outline)
        guard let saved else { return 1 }
        let widths = restored.widths == saved.widths, hidden = restored.hidden == saved.hidden, order = restored.order == saved.order
        say("\(widths && hidden && order && titlesOK ? "PASS" : "FAIL") autosave titlesAfterDrag=\(titlesOK ? "ok" : "SCRAMBLED") restored widths=\(widths ? "equal" : "DIFFERENT") hidden=\(hidden ? "equal" : "DIFFERENT") order=\(order ? "equal" : "DIFFERENT") saved=\(saved) restored=\(restored)")
        harness.window.contentViewController = nil
        harness.window.close()
        return widths && hidden && order && titlesOK ? 0 : 1
    }

    // MARK: - RememberedExpansion

    static func remembered() -> Int32 {
        let screen = "probe-\(getpid())"
        defer {
            UserDefaults.standard.removeObject(forKey: "outline.expanded.\(screen)")
            UserDefaults.standard.removeObject(forKey: "outline.expanded.\(screen).touched")
        }
        var failed = false
        func verdict(_ ok: Bool, _ line: String) { say((ok ? "PASS " : "FAIL ") + line); if !ok { failed = true } }
        let first = RememberedExpansion<Int>(screen: screen)
        first.seedIfUntouched([1, 2])
        verdict(first.ids == [1, 2], "remembered seed ids=\(first.ids.sorted())")
        let second = RememberedExpansion<Int>(screen: screen)
        verdict(second.ids == [1, 2], "remembered survivesRelaunch ids=\(second.ids.sorted())")
        second.binding.wrappedValue = [3]
        let third = RememberedExpansion<Int>(screen: screen)
        third.seedIfUntouched([9])
        verdict(third.ids == [3], "remembered neverSeedsAgainAfterTouch ids=\(third.ids.sorted())")
        return failed ? 1 : 0
    }
}
