import SwiftUI
import AnalyzersKit
import UIComponents

/// A run as one parent row that opens to what it moved, and each item's row.
extension UndoView {


    func runGroup(_ run: UndoRun) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expansion[run.id] ?? (run.restorable > 0 || openAll) },
            set: { expansion[run.id] = $0 })) {
            ForEach(run.children) { childRow($0) }
        } label: {
            runLabel(run)
        }
    }

    private func runLabel(_ run: UndoRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: run.isGuard ? "hand.raised.fill" : "trash")
                .foregroundStyle(run.isGuard ? Color.red : Color.secondary)
                .accessibilityHidden(true)  // decorative — the title names who did it
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
            Spacer(minLength: 8)
            if run.restorable > 0 {
                Button("Restore All") { restoreAll(run) }
                    .disabled(restoring)
                    .help("Put back the \(run.restorable) items that are still in the Trash")
            }
        }
    }

    private func childRow(_ child: UndoRun.Child) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(child.title)
                if !child.outcome.isEmpty {
                    Text(child.outcome).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let first = child.entries.first {
                action(for: child, first: first)
            }
        }
        .contextMenu {
            if let first = child.entries.first {
                switch first.source {
                case .trashed:
                    Button("Restore") { restore(child.restorable) }.disabled(child.restorable.isEmpty || restoring)
                case .stopped(let event):
                    Button("Copy Command") { copy(event) }
                }
            }
        }
    }

    /// Restore only where there is something to restore; an item that cannot be
    /// brought back has no button (the run says why, once).
    @ViewBuilder private func action(for child: UndoRun.Child, first: UndoEntry) -> some View {
        switch first.source {
        case .trashed:
            if !child.restorable.isEmpty {
                Button("Restore") { restore(child.restorable) }
                    .disabled(restoring)
            }
        case .stopped(let event):
            Button(copiedID == event.id ? "Copied" : "Copy Command") { copy(event) }
                .help(event.processName.count >= 140
                      ? "Recorded before the app kept full command lines, so part of it may be missing"
                      : "The command as the guard recorded it; you still supply the folder and environment")
        }
    }
}
