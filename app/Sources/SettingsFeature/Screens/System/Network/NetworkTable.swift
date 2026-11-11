import AppKit
import AnalyzersKit
import SwiftUI

/// One snapshot as an outline: an app is a row that opens to its programs (a
/// program that works alone is just a row), sortable by any column.
struct NetworkTable: View {
    let groups: [NetworkGroup]
    @Binding var selection: NetworkNode.ID?
    /// Which apps the person opened or closed; one nobody touched is open when
    /// the snapshot has only a few, closed when it has many.
    @Binding var opened: [NetworkGroup.ID: Bool]
    let onShowInFinder: (NetworkProcessRow) -> Void

    @State private var sortOrder = [KeyPathComparator(\NetworkNode.total, order: .reverse)]

    private var sortedGroups: [NetworkGroup] {
        groups.map(NetworkNode.init(group:)).sorted(using: sortOrder).compactMap(\.group)
    }

    private func members(_ group: NetworkGroup) -> [NetworkNode] {
        group.rows.map(NetworkNode.init(row:)).sorted(using: sortOrder)
    }

    var body: some View {
        Table(of: NetworkNode.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", sortUsing: KeyPathComparator(\.title, comparator: .localizedStandard)) { node in
                if let row = node.row {
                    Label { Text(row.name) } icon: { icon(for: row) }
                } else if let group = node.group {
                    GroupCell(name: group.name, countText: group.countText) {
                        if let first = group.rows.first { icon(for: first) }
                    }
                }
            }
            .width(min: 150, ideal: 240)
            TableColumn("Total", sortUsing: KeyPathComparator(\.total)) { node in
                Text(ByteSize.format(node.total)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Downloaded", sortUsing: KeyPathComparator(\.downloaded)) { node in
                Text(ByteSize.format(node.downloaded)).monospacedDigit()
            }
            .width(min: 80, ideal: 100)
            TableColumn("Uploaded", sortUsing: KeyPathComparator(\.uploaded)) { node in
                Text(ByteSize.format(node.uploaded)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Share", sortUsing: KeyPathComparator(\.share)) { node in
                Text(node.share, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
            TableColumn("Running", sortUsing: KeyPathComparator(\.runningText)) { node in
                if let row = node.row {
                    Label(row.runningTitle, systemImage: row.isRunning ? "circle.fill" : "circle")
                        .foregroundStyle(row.isRunning ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                } else {
                    Text(node.runningText).foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 90)
            TableColumn("PID", sortUsing: KeyPathComparator(\.pidValue)) { node in
                // a process id is an identifier: String keeps it free of a thousands separator
                Text(node.pidText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)
            TableColumn("Kind", sortUsing: KeyPathComparator(\.kindText)) { node in
                Text(node.kindText).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        } rows: {
            ForEach(sortedGroups) { group in
                if group.count == 1, let row = group.rows.first {
                    TableRow(NetworkNode(row: row))
                } else {
                    DisclosureTableRow(NetworkNode(group: group), isExpanded: Binding(
                        get: { opened[group.id] ?? (groups.filter { $0.count > 1 }.count <= 6) },
                        set: { opened[group.id] = $0 })) {
                        ForEach(members(group)) { TableRow($0) }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: NetworkNode.ID.self) { ids in
            if let row = row(ids) {
                Button("Show in Finder") { onShowInFinder(row) }.disabled(row.path == nil)
                Button("Copy Details") { copy(row) }
            }
        } primaryAction: { ids in
            if let row = row(ids) { onShowInFinder(row) }
        }
    }

    @ViewBuilder private func icon(for row: NetworkProcessRow) -> some View {
        if row.isRunning, let icon = NSRunningApplication(processIdentifier: pid_t(row.pid))?.icon {
            // an app icon is drawn at its own size: that is its job
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 16, height: 16)
        }
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
