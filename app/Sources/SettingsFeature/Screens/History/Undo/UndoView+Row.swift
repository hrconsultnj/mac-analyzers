import SwiftUI
import AnalyzersKit
import UIComponents

/// What a run's row and an item's row show and do, as the table's cells.

/// The name cell: a run's icon, who did it and when, what it holds and why it cannot
/// be restored (said once); an item's title and what happened to it.
struct UndoRowLabel: View {
    let node: UndoNode

    var body: some View {
        switch node.kind {
        case .day:
            EmptyView()   // a day is a section header, drawn full width by the table
        case .run(let run):
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(run.by).fontWeight(.medium)
                        if let when = run.when {
                            Text("· \(when.formatted(.dateTime.hour().minute()))").foregroundStyle(.secondary)
                        }
                    }
                    Text(run.summary).font(.caption).foregroundStyle(.secondary)
                    if let note = run.restoreNote {
                        Text(note).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } icon: {
                Image(systemName: run.isGuard ? "hand.raised.fill" : "trash")
                    .foregroundStyle(run.isGuard ? Color.red : Color.secondary)
            }
        case .item(let child):
            VStack(alignment: .leading, spacing: 1) {
                Text(child.title)
                if !child.outcome.isEmpty {
                    Text(child.outcome).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The action cell: Restore All on a run, Restore on an item, and for a stopped server
/// its command. Restore only where there is something to restore; an item that cannot
/// be brought back has no button (the run says why, once).
struct UndoRowAction: View {
    let node: UndoNode
    let view: UndoView

    var body: some View {
        switch node.kind {
        case .day:
            EmptyView()
        case .run(let run):
            if run.restorable > 0 {
                Button("Restore All") { view.restoreAll(run) }
                    .controlSize(.small)
                    .disabled(view.restoring)
                    .help("Put back the \(run.restorable) items that are still in the Trash")
            }
        case .item(let child):
            if let first = child.entries.first {
                switch first.source {
                case .trashed:
                    if !child.restorable.isEmpty {
                        Button("Restore") { view.restore(child.restorable) }
                            .controlSize(.small)
                            .disabled(view.restoring)
                    }
                case .stopped(let event):
                    Button(view.copiedID == event.id ? "Copied" : "Copy Command") { view.copy(event) }
                        .controlSize(.small)
                        .help(event.processName.count >= 140
                              ? "Recorded before the app kept full command lines, so part of it may be missing"
                              : "The command as the guard recorded it; you still supply the folder and environment")
                }
            }
        }
    }
}

/// The right-click menu of an item: the same action as its button.
struct UndoRowMenu: View {
    let nodes: [UndoNode]
    let ids: Set<String>
    let view: UndoView

    var body: some View {
        let picked = nodes.flatMap(\.flattened).filter { ids.contains($0.id) }
        if let node = picked.first, case .item(let child) = node.kind, let first = child.entries.first {
            switch first.source {
            case .trashed:
                Button("Restore") { view.restore(child.restorable) }
                    .disabled(child.restorable.isEmpty || view.restoring)
            case .stopped(let event):
                Button("Copy Command") { view.copy(event) }
            }
        }
    }
}
