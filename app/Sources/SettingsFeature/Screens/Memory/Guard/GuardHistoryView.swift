import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory Guard: what the guard saw and did, as a history to read — one
/// section per day with its total, a row for each thing in words (the app or
/// tool by name, what the guard did about it, when), repeats folded into one
/// row. A click opens the entry's own screen.
///
/// One job per file next to it:
///   GuardHistoryModel.swift   the history for the chosen window
///   GuardRowView.swift        one row, and the tile that carries its kind
///   GuardEntryScreen.swift    the pushed screen: what happened, the process, what the guard did and why
///   GuardLink.swift           the scope, search and window a deep link can ask for
///   AnalyzersKit/Memory/Guard/  the entries, grouped by day, so the probe can print them
struct GuardHistoryView: View {

    @Environment(Navigator.self) private var navigator
    @State private var model = GuardHistoryModel()
    @State private var scope: GuardHistory.Scope = .all
    @State private var search = ""
    /// The search the list is filtered by: what was typed, a moment after typing stops,
    /// because filtering tens of thousands of entries on every key makes typing lag.
    @State private var appliedSearch = ""
    @State private var selection: GuardHistory.Row.ID?

    var body: some View {
        let days = model.days(scope: scope, search: appliedSearch)
        let page = model.page(of: days)
        DataScreen(title: Names.Screen.memoryGuard, subtitle: subtitle(page)) { list(days: days, page: page) }
            .searchable(text: $search, prompt: "Search by name or process ID")
            .scopeTabsToolbar(screen: "guard", items: scopeItems, selection: $scope)
            .toolbar { toolbar }
            .onKeyPress(.return) {
                guard let id = selection, let row = model.history.row(id: id) else { return .ignored }
                open(row)
                return .handled
            }
            .task(id: search) {
                if search.isEmpty { appliedSearch = ""; return }
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { appliedSearch = search }
            }
            .task(id: model.window) {
                await model.refresh()
                applyPendingLink()
            }
            .onChange(of: navigator.pendingIntent) { applyPendingLink() }
            .screenActions(refresh: { Task { await model.refresh(force: true) } }, isActive: navigator.path.isEmpty)
    }

    /// The tabs, each with its symbol and how many events it holds in the chosen period.
    private var scopeItems: [ScopeTabItem<GuardHistory.Scope>] {
        GuardHistory.Scope.allCases.map { item in
            ScopeTabItem(value: item, title: item.title, symbol: item.symbol,
                         count: model.hasLoaded ? model.history.count(item) : nil)
        }
    }

    private func list(days: [GuardHistory.Day], page: GuardHistoryModel.Page) -> some View {
        List(selection: $selection) {
            ForEach(page.shown) { day in
                Section {
                    ForEach(day.rows) { row in
                        GuardRowView(row: row) { open(row) }
                            .tag(row.id)
                    }
                } header: {
                    HStack {
                        Text(day.title(now: Date())).font(.headline)
                        Text(day.summary).foregroundStyle(.secondary)
                    }
                }
            }
            if !page.isComplete {
                Button { model.showOlder(in: days) } label: {
                    Label(Names.Raw.showOlder, systemImage: "clock.arrow.circlepath")
                    Text("\(page.olderRows) earlier \(page.olderRows == 1 ? "row" : "rows")")
                        .foregroundStyle(.secondary)
                }
                .help("Show the next days of the \(model.window.title.lowercased())")
            }
        }
        .listStyle(.inset)
        .runHistoryRows()   // two-line rows at Activity's 44 points, the list's own minimum (not padding on each row)
        .overlay { emptyState(days) }
    }

    private func open(_ row: GuardHistory.Row) {
        navigator.push(.memory(.guardEntry(row.id)))
    }

    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: MemoryGroup.memoryGuard),
              let link = GuardLink(payload: payload) else { return }
        if let value = link.scope { scope = value }
        if let value = link.query { search = value; appliedSearch = value }
        if let value = link.window { model.window = value }
    }

    // MARK: - chrome

    /// "Last 90 days · 2 stopped · 14 alerts", or the truthful empty line.
    private func subtitle(_ page: GuardHistoryModel.Page) -> String {
        let history = model.history
        guard model.hasLoaded else { return "Reading the guard's log…" }
        if history.entries.isEmpty { return model.window.title }
        // the period actually shown; the period menu is how far back a person CAN go
        var parts = [model.window.title]
        if !page.isComplete, let oldest = page.shown.last?.day {
            let since = "Since \(oldest.formatted(.dateTime.month(.abbreviated).day()))"
            // a search reads the whole period; only how much of the result is shown is paged
            parts = appliedSearch.isEmpty ? [since]
                : ["Searching the \(model.window.title.lowercased())", "showing \(since.lowercased())"]
        } else if !appliedSearch.isEmpty {
            parts = ["Searching the \(model.window.title.lowercased())"]
        }
        let stopped = history.stoppedCount
        if stopped > 0 { parts.append(page.isComplete ? "\(stopped) stopped" : "\(stopped) stopped in the \(model.window.title.lowercased())") }
        // honest about how far back it goes when that is less than the period named
        if !history.coverage.reachedWindow, let oldest = history.coverage.oldest {
            parts = ["Since \(oldest.formatted(date: .abbreviated, time: .omitted))"] + parts.dropFirst()
        }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker(Names.Guard.show, selection: $model.window) {
                    ForEach(GuardHistoryModel.Window.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Button(Names.Monitor.refresh, systemImage: "arrow.clockwise") { Task { await model.refresh(force: true) } }
            } label: {
                // the period in force, with its icon: the same control as Monitor's lens
                Label(model.window.title, systemImage: "calendar")
            }
            .labelStyle(.titleAndIcon)
            .help("Choose how far back to look")
        }
    }

    @ViewBuilder private func emptyState(_ days: [GuardHistory.Day]) -> some View {
        if model.hasLoaded, days.isEmpty {
            if !appliedSearch.isEmpty {
                EmptyState.search(text: appliedSearch)
            } else if model.history.entries.isEmpty {
                EmptyState(Names.Guard.nothingToReport, systemImage: "shield.lefthalf.filled",
                                       description: Text("The guard has not stopped or flagged anything in the \(model.window.title.lowercased()). Quiet is good."))
            } else {
                EmptyState(Names.Guard.nothingHere, systemImage: scope == .crisisReports ? "stethoscope" : "line.3.horizontal.decrease",
                                       description: Text("Nothing in this view in the \(model.window.title.lowercased()). Try another."))
            }
        }
    }
}
