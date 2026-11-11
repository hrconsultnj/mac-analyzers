import SwiftUI
import AnalyzersKit

/// The ONLY place Monitor knows its table is a SwiftUI `Table` with
/// `DisclosureTableRow`s. It takes the tree, the sort, the selection, what is
/// open and the row actions, and nothing else in the Memory screens reaches
/// into it — so if the outline control changes (the app is measuring AppKit's
/// reentrancy warning to choose one control for every opening-group table),
/// this one file changes.
///
/// Two things it does on purpose, both measured (see `MonitorModel`):
///  - the table is given an `identity`; a new identity is a new table, which is
///    how a re-order or a filter change avoids AppKit's reentrant-delegate
///    warning. Selection and what is open survive (they are bindings); the
///    scroll position goes back to the top, and keyboard focus is not kept.
///  - the children of an open row are not changed under it — see
///    `MonitorTree.merge`; a row that has ended is drawn as ended.
struct MonitorOutline<Menu: View>: View {
    let rows: [MonitorRow]
    @Binding var sortOrder: [KeyPathComparator<MonitorRow>]
    @Binding var selection: MonitorRow.ID?
    let isExpanded: (String) -> Binding<Bool>
    let icons: [String: NSImage]
    let identity: String
    let rowFor: (MonitorRow.ID) -> MonitorRow?
    let begin: (MonitorStop) -> Void
    let open: (MonitorRow) -> Void
    @ViewBuilder let menu: (MonitorRow) -> Menu

    var body: some View {
        Table(of: MonitorRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(Names.Monitor.name, value: \.name) { row in
                MonitorNameCell(row: row, icon: icons[row.id])
            }
            .width(min: 150, ideal: 210)
            TableColumn(Names.Monitor.whatItIs) { row in
                Text(row.detailText).foregroundStyle(row.pendingNew + row.pendingEnded > 0 ? Color.orange : Color.secondary)
            }
            .width(min: 130, ideal: 260)
            TableColumn(Names.Monitor.memory, value: \.memoryBytes) { row in
                Text(row.memoryText)
                    .monospacedDigit()
                    .foregroundStyle(row.memoryBytes > 4 * 1_073_741_824 ? Color.orange : Color.secondary)
            }
            .width(min: 76, ideal: 84)
            TableColumn(Names.Monitor.cpu, value: \.cpuSort) { row in
                Text(row.cpuText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)
            TableColumn(Names.Monitor.pid, value: \.pidSort) { row in
                // a pid is an identifier: a String, so it never gains a thousands separator
                Text(row.pid.map { String($0) } ?? "").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 56, ideal: 64)
            TableColumn("") { row in stopControl(row) }
                .width(min: 50, ideal: 56)
        } rows: {
            ForEach(rows) { group in groupRows(group) }
        }
        .id(identity)
        .contextMenu(forSelectionType: MonitorRow.ID.self) { ids in
            if let row = ids.first.flatMap(rowFor) { menu(row) }
        } primaryAction: { ids in
            if let row = ids.first.flatMap(rowFor) { open(row) }
        }
    }

    // MARK: - rows (three levels: an app or tool, its parts or programs, their processes)

    @TableRowBuilder<MonitorRow> private func groupRows(_ group: MonitorRow) -> some TableRowContent<MonitorRow> {
        if group.hasChildren {
            DisclosureTableRow(group, isExpanded: isExpanded(group.id)) {
                ForEach(group.children) { child in childRows(child) }
            }
        } else {
            TableRow(group)
        }
    }

    @TableRowBuilder<MonitorRow> private func childRows(_ child: MonitorRow) -> some TableRowContent<MonitorRow> {
        if child.hasChildren {
            DisclosureTableRow(child, isExpanded: isExpanded(child.id)) {
                ForEach(child.children) { leaf in TableRow(leaf) }
            }
        } else {
            TableRow(child)
        }
    }

    // MARK: - the row's own Stop or Quit

    @ViewBuilder private func stopControl(_ row: MonitorRow) -> some View {
        if row.isEnded {
            Text(Names.Monitor.ended).font(.caption).foregroundStyle(.tertiary)
        } else if let verb = row.stopVerb {
            Button(verb) { begin(row.stop) }
                .buttonStyle(.borderless)
                .help(helpText(for: row))
        } else if let reason = row.lockedReason {
            Image(systemName: "lock.fill")
                .foregroundStyle(.tertiary)
                .help(reason)
                .accessibilityLabel(reason)
        }
    }

    private func helpText(for row: MonitorRow) -> String {
        switch row.stop {
        case .quitApp(let name, _, let count, _, _):
            "Quit \(name) and all \(count) of its processes — the same as ⌘Q, save prompts still appear"
        case .choosePrograms(let group, let programs):
            "Choose which of the \(programs.count) \(group) programs to stop"
        case .stopProgram(let program): "Ask \(program.label) to stop, along with everything it started"
        case .stopProcess(let process, _): "Ask \(process.friendlyName) to stop"
        case .none, .unavailable: ""
        }
    }
}

/// A row's name with the icon of the app it belongs to.
struct MonitorNameCell: View {
    let row: MonitorRow
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                // an app's own icon at row size: the icon is the actual job
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else if row.kind == .group || row.kind == .program {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            Text(row.name).foregroundStyle(row.isEnded ? Color.secondary : Color.primary)
        }
    }

    private var symbol: String {
        switch (row.kind, row.category) {
        case (_, .system): "gearshape"
        case (_, .tools): "terminal"
        default: "app"
        }
    }
}
