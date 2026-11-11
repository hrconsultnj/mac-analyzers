import SwiftUI
import AnalyzersKit
import UIComponents

/// Undo: what can be brought back, and what happened to the rest. Level 2 is the
/// two kinds of thing it holds (moved to the Trash, stopped dev servers); level 3
/// is the cleanup run (or the guard's day) as ONE parent row with its count and
/// total, opening to what it moved. Runs with something to restore come first
/// and open; runs whose Trash has been emptied are closed and say so once.
///
/// This file is the screen's state and its composition. One job per file:
///   UndoView+Row.swift       a run's parent row and an item's row
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
    /// Runs the person opened or closed; the rest follow the default (open when
    /// something in the run can still be restored).
    @State var expansion: [String: Bool] = [:]
    /// `undo:opened` opens every run (also what a link from a notification could ask for).
    @State var openAll = false

    private var shown: [UndoEntry] { entries.filter { $0.scope == scope } }

    var body: some View {
        Group {
            if loaded && shown.isEmpty {
                empty
            } else {
                List {
                    ForEach(UndoHistory.days(shown)) { day in
                        Section {
                            ForEach(day.runs) { run in runGroup(run) }
                        } header: {
                            HStack {
                                Text(day.title(now: Date()))
                                Spacer()
                                Text(day.summary).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Names.Screen.undo)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $scope) {
                    ForEach(UndoEntry.Scope.allCases, id: \.self) { kind in
                        Label("\(title(kind)) (\(entries.filter { $0.scope == kind }.count))",
                              systemImage: kind == .trashed ? "trash" : "hand.raised")
                            .labelStyle(.titleAndIcon)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .alert("Couldn't Restore", isPresented: Binding(get: { restoreError != nil },
                                                        set: { if !$0 { restoreError = nil } })) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .task {
            // `undo:trashed`, `undo:servers`, `undo:opened`: which kind, and whether every run is open
            switch navigator.takeIntent(for: HistoryGroup.undo) {
            case "servers": scope = .stopped
            case "opened": scope = .trashed; openAll = true
            default: break
            }
            await load()
        }
    }

    private func title(_ kind: UndoEntry.Scope) -> String {
        kind == .trashed ? "Moved to the Trash" : "Stopped Dev Servers"
    }

    private var subtitle: String {
        guard loaded else { return "Reading the history…" }
        let restorable = entries.filter(\.isRestorable).count
        return restorable > 0 ? "\(restorable) can still be restored" : "Nothing waiting to be restored"
    }

    @ViewBuilder private var empty: some View {
        switch scope {
        case .trashed:
            ContentUnavailableView("Nothing in the Trash From Cleanups", systemImage: "trash",
                                   description: Text("When a cleanup moves something to the Trash, it is listed here so you can put it back."))
        case .stopped:
            ContentUnavailableView("No Servers Stopped", systemImage: "hand.raised",
                                   description: Text("The guard has not stopped anything recently."))
        }
    }
}
