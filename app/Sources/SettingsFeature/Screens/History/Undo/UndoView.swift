import SwiftUI
import AnalyzersKit
import UIComponents

/// Undo: what can be brought back, and what happened to the rest. Level 2 is the
/// two kinds of thing it holds (moved to the Trash, stopped dev servers); level 3
/// is the cleanup run (or the guard's day) as ONE parent row with its count and
/// total, opening to what it moved. Runs with something to restore come first
/// and open; runs whose Trash has been emptied are closed and say so once.
///
/// One table for the whole history (`OutlineTable`): days are section-header rows,
/// runs are groups, items are rows; newest first, so nothing sorts.
///
/// This file is the screen's state and its composition. One job per file:
///   UndoNode.swift           the rows of the table, built from the history
///   UndoView+Row.swift       what a run's row and an item's row show and do
///   UndoView+Actions.swift   loading the history, restoring, copying a command
struct UndoView: View {

    @Environment(Navigator.self) var navigator
    @State var entries: [UndoEntry] = []
    @State var loaded = false
    @State var scope: UndoEntry.Scope = .trashed
    @State var restoreError: String?
    /// A restore is running: every Restore button is disabled until it finishes.
    @State var restoring = false
    @State var copiedID: String?
    /// The rows of the table for the chosen kind, built when the history or the kind changes.
    @State var nodes: [UndoNode] = []
    @State var selection: Set<String> = []
    /// Which runs are open, kept across window close and relaunch.
    @State var open = RememberedExpansion<String>(screen: "undo")

    private var tabItems: [ScopeTabItem<UndoEntry.Scope>] {
        UndoEntry.Scope.allCases.map { kind in
            ScopeTabItem(value: kind, title: title(kind), symbol: kind == .trashed ? "trash" : "hand.raised",
                         count: entries.filter { $0.scope == kind }.count)
        }
    }

    var body: some View {
        DataScreen(title: Names.Screen.undo, subtitle: subtitle) { content }
            .scopeTabsToolbar(screen: "undo", items: tabItems, selection: $scope)
            .alert("Couldn't Restore", isPresented: Binding(get: { restoreError != nil },
                                                            set: { if !$0 { restoreError = nil } })) {
                Button("OK") { restoreError = nil }
            } message: {
                Text(restoreError ?? "")
            }
            .task {
                // `undo:trashed`, `undo:servers`, `undo:opened`: which kind, and whether every run is open
                var openAll = false
                switch navigator.takeIntent(for: HistoryGroup.undo) {
                case "servers": scope = .stopped
                case "opened": scope = .trashed; openAll = true
                default: break
                }
                await load()
                if openAll { open.ids.formUnion(nodes.flatMap { $0.children ?? [] }.map(\.id)) }
            }
            .onChange(of: scope) { rebuild() }
    }

    @ViewBuilder private var content: some View {
        if loaded && nodes.isEmpty {
            empty
        } else {
            OutlineTable(nodes, children: \.children, selection: $selection,
                         expanded: open.binding, autosave: "undo") {
                OutlineColumn("name", Names.Column.name) { UndoRowLabel(node: $0) }
                    .lines { $0.lineCount }
                OutlineColumn("action", "") { node in UndoRowAction(node: node, view: self) }
                    .hideable(false)
                    .width(min: 110, ideal: 120, max: 160)
                    .alignment(.trailing)
            }
            .columnHeaders(.hidden)
            // a history of runs, not a table of values: no stripes behind the rows
            .alternatingRows(false)
            .sectionHeader { $0.header }
            .contextMenu({ ids in UndoRowMenu(nodes: nodes, ids: ids, view: self) })
            .emptyContent(isLoading: !loaded) { EmptyView() }
        }
    }

    /// Rebuilds the rows for the chosen kind, and keeps every day open as it appears:
    /// a day is a header, the person closes it only while looking.
    func rebuild() {
        nodes = UndoNode.tree(entries.filter { $0.scope == scope })
        open.ids.formUnion(nodes.map(\.id))
    }

    private func title(_ kind: UndoEntry.Scope) -> String {
        kind == .trashed ? "Moved to the Trash" : "Stopped Dev Servers"
    }

    private var subtitle: String {
        guard loaded else { return "Reading the history…" }
        let restorable = entries.filter(\.isRestorable).count
        return restorable > 0 ? "\(restorable) can still be restored" : "Nothing waiting to be restored"
    }

    /// Centred in the window (`DataScreen` puts its content at the top left).
    private var empty: some View {
        emptyMessage.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var emptyMessage: some View {
        switch scope {
        case .trashed:
            EmptyState("Nothing in the Trash From Cleanups", systemImage: "trash",
                       description: Text("When a cleanup moves something to the Trash, it is listed here so you can put it back."))
        case .stopped:
            EmptyState("No Servers Stopped", systemImage: "hand.raised",
                       description: Text("The guard has not stopped anything recently."))
        }
    }
}
