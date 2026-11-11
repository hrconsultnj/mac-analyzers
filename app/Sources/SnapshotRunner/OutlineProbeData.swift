import AppKit
import Foundation
import Observation
import SwiftUI
import UIComponents

struct ProbeRow: Identifiable {
    let id: Int
    var name: String
    var cpu: Double
    var mem: Int
    var kind: String
    var children: [ProbeRow]?
    /// A section header instead of a row (the section-header cases).
    var headerTitle: String?
}

/// Rows with unique ids: `levels` deep, `kids` per parent at every level below the top.
func makeProbeRows(parents: Int, kids: Int, levels: Int = 2) -> [ProbeRow] {
    var next = 0
    func make(_ level: Int, _ index: Int) -> ProbeRow {
        next += 1
        let id = next
        let isLeaf = level >= levels
        return ProbeRow(id: id,
                        name: isLeaf ? "proc \(id)" : "Parent \(id)",
                        cpu: Double((index + level) % 17), mem: (index * 37 + level * 11) % 900,
                        kind: isLeaf ? "Process" : "App",
                        children: isLeaf ? nil : (1...max(kids, 1)).map { make(level + 1, index * 10 + $0) })
    }
    return (0..<parents).map { make(1, $0) }
}

func probeFormat(_ cpu: Double) -> String { String(format: "%.1f", cpu) }

@MainActor
@Observable
final class ProbeModel {
    var rows: [ProbeRow]
    var expanded: Set<Int> = []
    var selection: Set<Int> = []
    var sortOrder: [KeyPathComparator<ProbeRow>] = [KeyPathComparator(\.name)]
    /// Every row, whatever the filter shows.
    let all: [ProbeRow]
    var nextID = 10_000_000

    init(rows: [ProbeRow]) {
        self.rows = rows
        all = rows
    }

    var parentIDs: [Int] { rows.map(\.id) }
    func newID() -> Int { nextID += 1; return nextID }
}

/// What a hosted cell saw, for the environment case.
@MainActor
enum ProbeRecorder {
    static var controlSizes: Set<String> = []
    static var objectValues: Set<Int> = []
}

@MainActor
@Observable
final class ProbeEnvObject {
    var value = 42
}

struct ProbeHostedCell: View {
    let text: String
    var body: some View { Text(text).lineLimit(1) }
}

struct ProbeEnvCell: View {
    let text: String
    @Environment(\.controlSize) private var controlSize
    @Environment(ProbeEnvObject.self) private var object

    var body: some View {
        ProbeRecorder.controlSizes.insert("\(controlSize)")
        ProbeRecorder.objectValues.insert(object.value)
        return Text(text).lineLimit(1)
    }
}

struct ProbeScreen: View {
    @Bindable var model: ProbeModel
    let hosted: Bool
    /// One per process, so what one probe saved is never restored into the next.
    var autosave = "probe-\(getpid())"
    var showsMenu = false
    /// Rows with a `headerTitle` draw as section headers.
    var headers = false
    /// Hosted cells that read the environment and record what they saw.
    var readsEnvironment = false
    /// Rows with an even id are two lines tall.
    var twoLineRows = false
    /// Called from inside the first column's text closure, which AppKit runs
    /// while it is asking for a cell (the in-callback case).
    var onFirstColumnText: (@MainActor (ProbeRow) -> Void)?

    var body: some View {
        let table = OutlineTable(model.rows, children: \.children, selection: $model.selection,
                                 sortOrder: $model.sortOrder, expanded: $model.expanded, autosave: autosave) {
            if readsEnvironment {
                OutlineColumn("name", "Name", sortUsing: KeyPathComparator(\ProbeRow.name)) { ProbeEnvCell(text: $0.name) }
                    .width(min: 120, ideal: 160)
                OutlineColumn("kind", "Kind", sortUsing: KeyPathComparator(\ProbeRow.kind)) { ProbeEnvCell(text: $0.kind) }
            } else if hosted {
                OutlineColumn("name", "Name", sortUsing: KeyPathComparator(\ProbeRow.name)) { ProbeHostedCell(text: $0.name) }
                    .width(min: 120, ideal: 160)
                OutlineColumn("cpu", "CPU", sortUsing: KeyPathComparator(\ProbeRow.cpu)) { ProbeHostedCell(text: probeFormat($0.cpu)) }
                    .alignment(.trailing).width(min: 40, ideal: 60)
                OutlineColumn("mem", "Memory", sortUsing: KeyPathComparator(\ProbeRow.mem)) { ProbeHostedCell(text: "\($0.mem) MB") }
                    .alignment(.trailing).width(min: 60, ideal: 80)
                OutlineColumn("kind", "Kind", sortUsing: KeyPathComparator(\ProbeRow.kind)) { ProbeHostedCell(text: $0.kind) }
                    .width(min: 60, ideal: 80)
            } else {
                let name = OutlineColumn("name", "Name", text: { row in onFirstColumnText?(row); return row.name },
                                         sortUsing: KeyPathComparator(\ProbeRow.name))
                    .width(min: 120, ideal: 160)
                // only the lines case declares lines: the other probes measure a table that does not
                if twoLineRows { name.lines { $0.id % 2 == 0 || $0.kind == "Two" ? 2 : 1 } } else { name }
                OutlineColumn("cpu", "CPU", text: { probeFormat($0.cpu) }, sortUsing: KeyPathComparator(\ProbeRow.cpu))
                    .alignment(.trailing).monospacedDigits().width(min: 40, ideal: 60)
                OutlineColumn("mem", "Memory", text: { "\($0.mem) MB" }, sortUsing: KeyPathComparator(\ProbeRow.mem))
                    .alignment(.trailing).monospacedDigits().width(min: 60, ideal: 80)
                OutlineColumn("kind", "Kind", text: { $0.kind }, sortUsing: KeyPathComparator(\ProbeRow.kind))
                    .textStyle { _ in .secondary }.width(min: 60, ideal: 80)
            }
        }
        let menued = showsMenu
            ? AnyView(table.contextMenu({ ids in Button("Act on \(ids.count)") {} }, primaryAction: { _ in }))
            : AnyView(table)
        if headers {
            // a typed view per branch is not needed here: the probe only draws it
            sectioned()
        } else {
            menued
        }
    }
}

extension ProbeScreen {
    /// The same table with `headerTitle` rows drawn as section headers.
    @ViewBuilder
    fileprivate func sectioned() -> some View {
        OutlineTable(model.rows, children: \.children, selection: $model.selection,
                     expanded: $model.expanded, autosave: autosave + ".sections") {
            OutlineColumn("name", "Name", text: { $0.name })
            OutlineColumn("mem", "Memory", text: { "\($0.mem) MB" }).alignment(.trailing)
        }
        .sectionHeader { $0.headerTitle.map { OutlineSectionHeader(title: $0, summary: "\($0.count) characters") } }
    }
}
