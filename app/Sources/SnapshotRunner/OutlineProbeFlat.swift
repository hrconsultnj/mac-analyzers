import AppKit
import Foundation
import Observation
import SwiftUI

/// A11: the SwiftUI controls the design leaves in place — a flat `Table`
/// re-sorted in place, and a `List` growing by 200 rows — counted the same way.
/// The counts decide the order of the last migration steps and the paging rule.
struct ProbeFlatTable: View {
    @Bindable var model: ProbeModel

    var body: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name)
            TableColumn("CPU", value: \.cpu) { Text(probeFormat($0.cpu)) }
            TableColumn("Memory", value: \.mem) { Text("\($0.mem) MB") }
            TableColumn("Kind", value: \.kind)
        }
    }
}

struct ProbeFlatList: View {
    @Bindable var model: ProbeModel

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.rows) { Text($0.name).tag($0.id) }
        }
    }
}

@MainActor
enum ProbeFlat {
    static func run(_ spec: String) -> Int32 {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 2, let count = Int(parts[1]) else {
            FileHandle.standardError.write(Data("usage: a11:tableSort:<n> | a11:listAppend:<n>\n".utf8))
            return 2
        }
        let label = "\(parts[0])\(count)"
        switch parts[0] {
        case "tableSort":
            let model = ProbeModel(rows: makeProbeRows(parents: count, kids: 0, levels: 1).map { row in
                var flat = row
                flat.children = nil
                return flat
            })
            let harness = ProbeHarness(ProbeFlatTable(model: model))
            _ = harness
            mark("begin \(label)")
            model.rows.sort { $0.mem > $1.mem }
            model.sortOrder = [KeyPathComparator(\.mem, order: .reverse)]
            let ms = settle()
            spin(0.4)
            mark("end \(label)")
            say("a11 \(label) rows=\(count) settleMs=\(Int(ms))")
        case "listAppend":
            let all = makeProbeRows(parents: count + 200, kids: 0, levels: 1)
            let model = ProbeModel(rows: Array(all.prefix(count)))
            let harness = ProbeHarness(ProbeFlatList(model: model))
            _ = harness
            mark("begin \(label)")
            model.rows = all
            let ms = settle()
            spin(0.4)
            mark("end \(label)")
            say("a11 \(label) rows=\(count)->\(count + 200) settleMs=\(Int(ms))")
        default:
            return 2
        }
        return 0
    }
}
