import SwiftUI
import AnalyzersKit
import UIComponents

/// Activity: every run, whoever started it — you, the schedule, the guard or
/// Terminal. A table with scopes and search, and an inspector for the selected
/// run. This is the screen the old Logs landing became: it still lists every
/// log with its latest run, and a row still leads to that log's screen.
///
/// One job per file next to it:
///   ActivityModel.swift           the rows (joined from the store, the index and the logs), scopes
///   ActivityInspector.swift       live output and Stop, or the finished result
///   JobScreen.swift               one job pushed from the toolbar, a notification or a link
///   JobStatusToolbarItem.swift    the shell's status item
///   JobFinishNotifier.swift       the notification when a job ends behind a closed window
///   AnalyzersKit/Activity/        the join itself, so it can be tested without a window
struct ActivityView: View {

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var model = ActivityModel()
    @State private var scope: ActivityScope = .all
    @State private var query = ""
    @State private var selection: ActivityRow.ID?
    @State private var sortOrder = [KeyPathComparator(\ActivityRow.startedSort, order: .reverse)]
    @State private var showInspector = true

    /// What the scope and search leave, in the user's sort. Sorting happens
    /// here, when the rows or the sort change, and nowhere else.
    private var visible: [ActivityRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.rows
            .filter { scope.includes($0) }
            .filter { needle.isEmpty || $0.title.lowercased().contains(needle) || $0.result.lowercased().contains(needle) }
            .sorted(using: sortOrder)
    }

    private var selectedRow: ActivityRow? {
        selection.flatMap { id in model.rows.first { $0.id == id } }
    }

    /// Changes only when a job moves between queued, running and finished.
    private var storeStamp: [JobStamp] { store.jobs.map { JobStamp($0) } }

    var body: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Task", value: \.title) { row in
                Label {
                    HStack(spacing: Tokens.Space.s) {
                        Text(row.title)
                        if let intent = row.intent, intent != .run {
                            BadgeCapsule(text: intent.title.uppercased(), color: row.tint)
                        }
                    }
                } icon: {
                    Image(systemName: row.symbol).foregroundStyle(row.tint)
                }
            }
            TableColumn("Started", value: \.startedSort) { row in
                Text(row.started.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            TableColumn("Duration", value: \.durationSort) { row in
                DurationCell(row: row)
            }
            TableColumn("Triggered by", value: \.triggerName) { row in
                Text(row.trigger.rawValue).foregroundStyle(.secondary)
            }
            TableColumn("Result", value: \.result) { row in
                HStack(spacing: Tokens.Space.s) {
                    Text(row.result).lineLimit(1)
                    if row.needsReview { BadgeCapsule(text: "REVIEW", color: .orange) }
                }
                .help(row.result)
            }
            TableColumn("Status", value: \.statusName) { row in
                StatusCell(row: row)
            }
        }
        .contextMenu(forSelectionType: ActivityRow.ID.self) { ids in
            if let row = ids.first.flatMap(rowFor) { menu(for: row) }
        } primaryAction: { ids in
            if let row = ids.first.flatMap(rowFor) { open(row) }
        }
        .overlay {
            if model.hasLoaded, visible.isEmpty {
                ContentUnavailableView(scope == .all && query.isEmpty ? "Nothing has run yet" : "No matching runs",
                                       systemImage: "list.bullet.rectangle",
                                       description: Text(scope == .all && query.isEmpty
                                                         ? "Cleanups, checks and reports appear here as they run."
                                                         : "Try another scope or search."))
            }
        }
        .navigationTitle("Activity")
        .navigationSubtitle(subtitle)
        .searchable(text: $query, prompt: "Search task or result")
        .searchScopes($scope) {
            ForEach(ActivityScope.allCases) { scope in Text(scope.title).tag(scope) }
        }
        .inspector(isPresented: $showInspector) {
            ActivityInspector(row: selectedRow, model: model)
                .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refresh(store: store) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Read the logs again")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(EngineLog.allCases) { log in
                        Button { navigator.open(target: "log:\(log.rawValue)") } label: {
                            Label(log.title, systemImage: log.symbol)
                        }
                    }
                } label: {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
                .help("Open one log's own screen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help(showInspector ? "Hide the inspector" : "Show the inspector")
            }
        }
        .task { await model.refresh(store: store) }
        .onChange(of: storeStamp) { Task { await model.refresh(store: store) } }
    }

    // MARK: - rows

    private func rowFor(_ id: ActivityRow.ID) -> ActivityRow? { model.rows.first { $0.id == id } }

    private var subtitle: String {
        let running = model.rows.filter(\.isRunning).count
        let total = model.rows.filter { $0.status != .none }.count
        return running > 0 ? "\(running) running · \(total) runs" : "\(total) runs"
    }

    /// A row leads to its task's own screen: the log's pane for a log, the
    /// owning screen for a report or a snapshot.
    private func open(_ row: ActivityRow) {
        if let target = row.ownerTarget {
            navigator.open(target: target)
        } else if let id = row.jobID {
            navigator.push(.job(id))
        }
    }

    @ViewBuilder private func menu(for row: ActivityRow) -> some View {
        if let target = row.ownerTarget {
            Button("Open \(row.title)") { navigator.open(target: target) }
        }
        if let id = row.jobID {
            Button("Open Job Details") { navigator.push(.job(id)) }
        }
        if let url = row.log?.url {
            Button("Show Raw Log") { GuardControl.openLog(url) }
        }
    }
}

// MARK: - cells

/// Elapsed time. A running job's counts itself up (the system redraws the
/// text), so the table's data is untouched while it runs.
private struct DurationCell: View {
    let row: ActivityRow

    var body: some View {
        Group {
            if row.status == .running, let started = row.started {
                Text(started, style: .timer)
            } else if let duration = row.duration {
                Text(Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
            } else {
                Text("—")
            }
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

private struct StatusCell: View {
    let row: ActivityRow

    var body: some View {
        switch row.status {
        case .running:
            HStack(spacing: Tokens.Space.s) {
                ProgressView().controlSize(.small)
                Text("Running")
            }
        case .queued:
            Label("Queued", systemImage: "clock").foregroundStyle(.secondary)
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(Tokens.Status.safe.tint)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tokens.Status.caution.tint)
        case .stopped:
            Label("Stopped", systemImage: "stop.circle.fill").foregroundStyle(Tokens.Status.inert.tint)
        case .none:
            Text("—").foregroundStyle(.secondary)
        }
    }
}
