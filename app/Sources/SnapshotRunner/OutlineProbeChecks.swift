import AppKit
import Foundation
import SwiftUI
import UIComponents

/// A4 (what survives an update) and A6 (the pure diff).
@MainActor
enum ProbeChecks {

    // MARK: - looking at a table

    struct Look {
        var selection: Set<String>
        var open: Set<String>
        var anchor: String?
        var anchorOffset: CGFloat
        var selectedName: String?
        var selectedOffset: CGFloat
        var focusIsOutline: Bool
        /// The scroll position is at the first or last it can have, where keeping an offset is impossible.
        var atScrollLimit: Bool
    }

    static func name(_ outline: NSOutlineView, row: Int) -> String {
        (outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue ?? "?"
    }

    static func look(_ harness: ProbeHarness) -> Look {
        let outline = harness.outline!
        let top = outline.visibleRect.minY
        let range = outline.rows(in: outline.visibleRect)
        let visible = range.location..<(range.location + range.length)
        let firstFull = visible.first { outline.rect(ofRow: $0).minY >= top - 0.5 }
        var selection = Set<String>()
        for row in outline.selectedRowIndexes { selection.insert(name(outline, row: row)) }
        var open = Set<String>()
        for row in 0..<outline.numberOfRows where outline.isItemExpanded(outline.item(atRow: row)) {
            open.insert(name(outline, row: row))
        }
        let selected = visible.first { outline.isRowSelected($0) }
        return Look(selection: selection, open: open,
                    anchor: firstFull.map { name(outline, row: $0) },
                    anchorOffset: firstFull.map { outline.rect(ofRow: $0).minY - top } ?? 0,
                    selectedName: selected.map { name(outline, row: $0) },
                    selectedOffset: selected.map { outline.rect(ofRow: $0).minY - top } ?? 0,
                    focusIsOutline: harness.window.firstResponder === outline,
                    atScrollLimit: harness.window.contentView.flatMap(findScroll(in:)).map { scroll in
                        let y = scroll.contentView.bounds.origin.y
                        let lowest = -scroll.contentInsets.top
                        let highest = outline.frame.height - scroll.contentView.bounds.height + scroll.contentInsets.bottom
                        return y <= lowest + 0.5 || y >= highest - 0.5
                    } ?? false)
    }

    /// 200 x 5, forty groups open, scrolled into the middle, a visible row
    /// selected, the outline the first responder.
    static func prepared(_ options: ProbeOptions) -> (ProbeModel, ProbeHarness) {
        let model = ProbeModel(rows: makeProbeRows(parents: options.parents, kids: options.kids))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        let outline = harness.outline!
        model.expanded = Set(model.parentIDs.prefix(40))
        _ = settle(); spin(0.2)
        outline.scrollRowToVisible(150)
        _ = settle()
        let range = outline.rows(in: outline.visibleRect)
        outline.selectRowIndexes(IndexSet(integer: range.location + 4), byExtendingSelection: false)
        harness.window.makeFirstResponder(outline)
        _ = settle(); spin(0.2)
        return (model, harness)
    }

    static func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is NSOutlineView { return scroll }
        for sub in view.subviews { if let found = findScroll(in: sub) { return found } }
        return nil
    }

    static func format(_ value: CGFloat) -> String { String(format: "%.1f", Double(value)) }

    // MARK: - A4

    static func preserve(_ options: ProbeOptions) -> Int32 {
        var failed = false
        func verdict(_ ok: Bool, _ line: String) {
            say((ok ? "PASS " : "FAIL ") + line)
            if !ok { failed = true }
        }

        for kind in ["values", "resort"] {
            let (model, harness) = prepared(options)
            let before = look(harness)
            ProbeActions.perform(kind, model: model, outline: harness.outline)
            _ = settle(); spin(0.3)
            let after = look(harness)
            // a values refresh keeps the first visible row where it was; a re-sort keeps the SELECTED row
            let delta = kind == "values" ? after.anchorOffset - before.anchorOffset : after.selectedOffset - before.selectedOffset
            let sameRow = kind == "values" ? after.anchor == before.anchor : after.selectedName == before.selectedName
            // a re-sort that puts the selected row where the scroll cannot hold it (the top, the end) keeps it as close as it can
            let held = abs(delta) < 0.5 || (kind == "resort" && after.atScrollLimit)
            verdict(before.selection == after.selection && before.open == after.open && sameRow && held && after.focusIsOutline,
                    "preserve \(kind) selection=\(before.selection == after.selection ? "equal" : "CHANGED") expansion=\(before.open == after.open ? "equal" : "CHANGED") anchorDelta=\(format(delta))\(abs(delta) >= 0.5 && after.atScrollLimit ? " (scroll limit)" : "") focus=\(after.focusIsOutline ? "outline" : "LOST")")
        }

        do {
            let (model, harness) = prepared(options)
            let before = look(harness)
            ProbeActions.perform("filter10", model: model, outline: harness.outline)
            _ = settle(); spin(0.3)
            let during = look(harness)
            let left = before.selection.subtracting(during.selection).sorted()
            say("INFO preserve filter selectionLeft=\(left) open=\(during.open.count) focus=\(during.focusIsOutline ? "outline" : "LOST")")
            ProbeActions.perform("filterBack", model: model, outline: harness.outline)
            _ = settle(); spin(0.3)
            let back = look(harness)
            verdict(back.anchor == before.anchor && abs(back.anchorOffset - before.anchorOffset) < 0.5 && back.open == before.open && back.focusIsOutline,
                    "preserve filterBack anchor=\(before.anchor ?? "nil")->\(back.anchor ?? "nil") anchorDelta=\(format(back.anchorOffset - before.anchorOffset)) expansion=\(back.open == before.open ? "equal" : "CHANGED") focus=\(back.focusIsOutline ? "outline" : "LOST")")
        }

        do {
            let (model, harness) = prepared(options)
            let before = look(harness)
            ProbeActions.perform("expandAll", model: model, outline: harness.outline)
            _ = settle(); spin(0.3)
            let after = look(harness)
            verdict(after.anchor == before.anchor && abs(after.anchorOffset - before.anchorOffset) < 0.5 && before.selection == after.selection && after.focusIsOutline,
                    "preserve expandAll anchor=\(before.anchor ?? "nil")->\(after.anchor ?? "nil") anchorDelta=\(format(after.anchorOffset - before.anchorOffset)) selection=\(before.selection == after.selection ? "equal" : "CHANGED") focus=\(after.focusIsOutline ? "outline" : "LOST") open=\(before.open.count)->\(after.open.count)")
        }
        return failed ? 1 : 0
    }

    // MARK: - A6

    /// The longest increasing subsequence length by the slow, obviously right way.
    static func slowLIS(_ values: [Int]) -> Int {
        var best = [Int](repeating: 1, count: values.count)
        var longest = 0
        for i in values.indices {
            for j in 0..<i where values[j] < values[i] && best[j] + 1 > best[i] { best[i] = best[j] + 1 }
            longest = max(longest, best[i])
        }
        return longest
    }

    /// The updater's order — removals, moves of the ones outside the LIS, inserts — on bare ids.
    static func simulate(old: [Int], new: [Int], level: OutlineDiff.Level<Int>) -> [Int] {
        var current = old
        for index in level.removed.reversed() { current.remove(at: index) }
        var previous: Int?
        for (index, id) in level.survivorsNew.enumerated() {
            defer { previous = id }
            if level.stays[index] { continue }
            current.remove(at: current.firstIndex(of: id)!)
            let to = previous.map { current.firstIndex(of: $0)! + 1 } ?? 0
            current.insert(id, at: to)
        }
        for index in level.inserted { current.insert(new[index], at: index) }
        return current
    }

    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    static func diff() -> Int32 {
        var failed = false
        var rng = Seeded(state: 42)
        let n = 6000
        let ids = Array(0..<n)
        let mixedNew = Array(ids.dropFirst(1000)) + Array(n..<(n + 1000))
        let cases: [(String, [Int], [Int])] = [
            ("reversed", ids, ids.reversed()),
            ("shuffled", ids, ids.shuffled(using: &rng)),
            ("removed1000+inserted1000+shuffled", ids, mixedNew.shuffled(using: &rng)),
        ]
        for (label, old, new) in cases {
            var samples: [Double] = []
            var level = OutlineDiff.level(old: old, new: new)
            for _ in 0..<5 {
                let start = cpuMilliseconds()
                level = OutlineDiff.level(old: old, new: new)
                samples.append(cpuMilliseconds() - start)       // CPU time: the algorithm, not the Mac's other work
            }
            let milliseconds = samples.sorted()[samples.count / 2]
            var position: [Int: Int] = [:]
            for (index, id) in level.survivorsOld.enumerated() { position[id] = index }
            let slow = slowLIS(level.survivorsNew.map { position[$0]! })
            let movesOK = level.moveCount == level.survivorsNew.count - slow
            let rebuilt = simulate(old: old, new: new, level: level)
            let orderOK = rebuilt == new
            let fast = milliseconds <= 5
            if !(movesOK && orderOK && fast) { failed = true }
            say("\(movesOK && orderOK && fast ? "PASS" : "FAIL") diff \(label) n=\(n) cpuMs=\(String(format: "%.2f", milliseconds)) (budget 5) moves=\(level.moveCount) n-LIS=\(level.survivorsNew.count - slow) movesEqualNminusLIS=\(movesOK) appliedOrderEqualsNew=\(orderOK)")
        }
        return failed ? 1 : 0
    }
}
