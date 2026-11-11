import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// One snapshot as an outline: an app is a row that opens to its programs (a
/// program that works alone is just a row), sortable by any column. The table is
/// the shared `OutlineTable`; this file only says which columns and what each shows.
struct NetworkTable: View {
    let groups: [NetworkGroup]
    @Binding var selection: NetworkNode.ID?
    /// Which apps are open, kept across window close and relaunch.
    let expansion: RememberedExpansion<String>
    let onShowInFinder: (NetworkProcessRow) -> Void

    @State private var sortOrder = [KeyPathComparator(\NetworkNode.total, order: .reverse)]

    var body: some View {
        let nodes = NetworkNode.tree(groups, sort: sortOrder)
        OutlineTable(nodes, children: \.children, selection: $selection, sortOrder: $sortOrder,
                     expanded: expansion.binding, autosave: "network") {
            OutlineColumn("name", Names.Column.name,
                          sortUsing: KeyPathComparator(\NetworkNode.title, comparator: .localizedStandard)) { node in
                NetworkNodeName(node: node)
            }
            .width(min: 150, ideal: 240)
            OutlineColumn("total", Names.Column.total, text: \.totalText,
                          sortUsing: KeyPathComparator(\NetworkNode.total))
                .alignment(.trailing).monospacedDigits()
                .width(min: 70, ideal: 90)
            OutlineColumn("downloaded", Names.Column.downloaded, text: \.downloadedText,
                          sortUsing: KeyPathComparator(\NetworkNode.downloaded))
                .alignment(.trailing).monospacedDigits()
                .width(min: 80, ideal: 100)
            OutlineColumn("uploaded", Names.Column.uploaded, text: \.uploadedText,
                          sortUsing: KeyPathComparator(\NetworkNode.uploaded))
                .alignment(.trailing).monospacedDigits()
                .width(min: 70, ideal: 90)
            OutlineColumn("share", Names.Column.share, text: \.shareText,
                          sortUsing: KeyPathComparator(\NetworkNode.share))
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                .width(min: 50, ideal: 60)
            OutlineColumn("running", Names.Column.running,
                          sortUsing: KeyPathComparator(\NetworkNode.runningText)) { node in
                if let row = node.row {
                    Label(row.runningTitle, systemImage: row.isRunning ? "circle.fill" : "circle")
                        .foregroundStyle(row.isRunning ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                } else {
                    Text(node.runningText).foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 90)
            OutlineColumn("pid", Names.Column.pid, text: \.pidText,
                          sortUsing: KeyPathComparator(\NetworkNode.pidValue))
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                .width(min: 50, ideal: 70)
            OutlineColumn("kind", Names.Column.kind, text: \.kindText,
                          sortUsing: KeyPathComparator(\NetworkNode.kindText))
                .textStyle { _ in .secondary }
                .width(min: 90, ideal: 110)
        }
        .contextMenu({ ids in
            if let row = row(ids) {
                Button("Show in Finder") { onShowInFinder(row) }.disabled(row.path == nil)
                Button("Copy Details") { copy(row) }
            }
        }, primaryAction: { ids in
            if let row = row(ids) { onShowInFinder(row) }
        })
    }

    private func row(_ ids: Set<NetworkNode.ID>) -> NetworkProcessRow? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return groups.lazy.flatMap(\.rows).first { $0.id == id }
    }

    private func copy(_ row: NetworkProcessRow) {
        let text = "\(row.name) — downloaded \(ByteSize.format(row.downloaded)), uploaded \(ByteSize.format(row.uploaded)), process \(row.pid)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension NetworkProcessRow {
    var runningTitle: String { isRunning ? "Yes" : "No" }
}
