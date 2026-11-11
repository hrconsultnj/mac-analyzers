import SwiftUI
import AnalyzersKit
import UIComponents

/// The ONLY place Monitor knows how its table is drawn: one `OutlineTable`, the app's table for rows
/// that open. It takes the tree, the sort, the selection, what is open and the row actions; nothing
/// else in the Memory screens reaches into it.
///
/// What the table does for Monitor, and what Monitor no longer does for itself:
///  - a re-sort keeps scroll position, selection and keyboard focus (no rebuilding the table);
///  - rows appear and leave inside an open group live (no holding them back);
///  - the table exists before it has rows (`emptyContent`), and shows a progress indicator until the
///    first reading.
struct MonitorOutline<Menu: View>: View {
    let rows: [MonitorRow]
    @Binding var sortOrder: [KeyPathComparator<MonitorRow>]
    @Binding var selection: MonitorRow.ID?
    let expanded: Binding<Set<String>>
    let icons: [String: NSImage]
    let isLoading: Bool
    let empty: AnyView
    let rowFor: (MonitorRow.ID) -> MonitorRow?
    let begin: (MonitorStop) -> Void
    let open: (MonitorRow) -> Void
    @ViewBuilder let menu: (MonitorRow) -> Menu

    var body: some View {
        // The shared table fits its columns to the room (section 11 of the table's report): "What It Is", which the
        // details panel says again for the selected row, is the one that can go (and the Process ID, which starts
        // hidden); Name, Memory, CPU and Stop or Quit are essential, the default, and never leave the screen.
        OutlineTable(rows, children: \.childRows, selection: $selection, sortOrder: $sortOrder,
                     expanded: expanded, autosave: "monitor") {
            OutlineColumn("name", Names.Monitor.name, sortUsing: KeyPathComparator(\MonitorRow.name)) { row in
                MonitorNameCell(row: row, icon: icons[row.id])
            }
            .width(min: 130, ideal: 210)
            .typeSelect { $0.name }
            OutlineColumn("what", Names.Monitor.whatItIs, text: { $0.detail })
                .textStyle { _ in .secondary }
                .width(min: 130, ideal: 260)
                .fit(.optional)
            OutlineColumn("memory", Names.Monitor.memory, text: { $0.memoryText },
                          sortUsing: KeyPathComparator(\MonitorRow.memoryBytes))
                .alignment(.trailing).monospacedDigits()
                .textStyle { $0.memoryBytes > 4 * 1_073_741_824 ? .warning : .secondary }
                .width(min: 72, ideal: 80)
            OutlineColumn("cpu", Names.Monitor.cpu, text: { $0.cpuText },
                          sortUsing: KeyPathComparator(\MonitorRow.cpuSort))
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                .width(min: 56, ideal: 62)
            // a pid is an identifier: text, so it never gains a thousands separator
            OutlineColumn("pid", Names.Monitor.pid, text: { $0.pid.map { String($0) } ?? "" },
                          sortUsing: KeyPathComparator(\MonitorRow.pidSort))
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                .width(min: 56, ideal: 64)
                .fit(.optional)
                .defaultHidden()
            OutlineColumn("stop", "") { row in stopControl(row) }
                .hideable(false)
                .width(min: 48, ideal: 52)
        }
        .contextMenu({ ids in
            if let row = ids.first.flatMap(rowFor) { menu(row) }
        }, primaryAction: { ids in
            if let row = ids.first.flatMap(rowFor) { open(row) }
        })
        .emptyContent(isLoading: isLoading) { empty }
    }

    // MARK: - the row's own Stop or Quit

    @ViewBuilder private func stopControl(_ row: MonitorRow) -> some View {
        if row.isEnded {
            Text(Names.Monitor.ended).font(.caption).foregroundStyle(.tertiary)
        } else if let verb = row.stopVerb {
            Button(verb) { begin(row.stop) }
                .buttonStyle(.borderless)
                .help(helpText(for: row))
        } else if let reason = row.lockedReason, row.category != .system {
            // a lock says "this one is protected" (a live coding session); on a macOS service it would be on
            // most of the table and say nothing, so those rows carry no control at all
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
