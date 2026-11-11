import SwiftUI
import AnalyzersKit
import UIComponents

/// What a person can do with a run's row, written once: open its screen, review
/// or preview again, stop it, copy its details, see its raw output. Activity,
/// a task screen's run history and anything else that lists runs get their rows
/// from here, so a run behaves the same wherever it is shown.
@MainActor
struct RunRowActions {
    let store: JobStore
    let navigator: Navigator
    let model: ActivityModel

    func job(for row: ActivityRow) -> Job? {
        row.jobID.flatMap { id in store.jobs.first { $0.id == id } }
    }

    /// A running job's current step, read from the job itself so it moves while
    /// the list's data does not.
    func liveLine(_ row: ActivityRow) -> String? {
        guard row.status == .running, let job = job(for: row) else { return nil }
        return job.step ?? row.line
    }

    func lines(for row: ActivityRow) -> [String] { job(for: row)?.lines ?? model.lines(for: row) }

    /// A row leads to its own run screen; a task that has not run yet leads to
    /// the task's screen.
    func open(_ row: ActivityRow) {
        if let route = row.route {
            navigator.push(route)
        } else if let target = row.ownerTarget {
            navigator.open(target: target)
        }
    }

    /// A waiting preview's task screen, where it is reviewed and applied.
    func review(_ row: ActivityRow) {
        if let target = row.reviewTarget { navigator.open(target: target) }
    }

    func stop(_ row: ActivityRow) { job(for: row)?.cancel() }

    /// The row, with its click, its Review and Stop buttons and its context menu.
    func rowView(_ row: ActivityRow, now: Date) -> some View {
        ActivityRowView(row: row, now: now, liveLine: liveLine(row), onOpen: { open(row) },
                        onReview: row.needsReview ? { review(row) } : nil,
                        onStop: row.isRunning ? { stop(row) } : nil)
            .tag(row.id)
            .contextMenu { menu(for: row) }
    }

    @ViewBuilder func menu(for row: ActivityRow) -> some View {
        Button("Open") { open(row) }
        if row.reviewTarget != nil {
            if row.needsReview {
                Button("Review") { review(row) }
            } else if row.intent == .preview, row.findings > 0 {
                Button("Preview Again") { review(row) }
            }
        }
        if let target = row.ownerTarget, row.route != nil {
            Button("Open \(row.title)") { navigator.open(target: target) }
        }
        if row.route != nil {
            Button("Copy Details") { ActivityDetails.copy(row, lines: lines(for: row)) }
            Button("Show Raw Output") { showRaw(row) }
        }
        if row.isRunning {
            Divider()
            Button("Stop", role: .destructive) { stop(row) }
        }
    }

    /// The run's own raw text, one level down.
    func showRaw(_ row: ActivityRow) {
        if case .logged(let log, let header, let ordinal) = row.source {
            navigator.push(.overview(.raw(.run(RunReference(log: log, header: header, ordinal: ordinal)))))
        } else if let id = row.jobID {
            navigator.push(.overview(.raw(.job(id))))
        }
    }
}

/// A task's runs: the one running or waiting now (with its Stop) above the past ones,
/// the same rows Activity shows, filtered to one task and grouped by day with each day's
/// total, each row opening that run's own screen. It goes inside a `List` or a `Form`
/// (it returns sections):
///
///     List {
///         RunHistoryList(kinds: [.storageClean], logs: [.storageClean],
///                        emptyText: "Nothing has run here yet.", limit: 8)
///     }
///
/// `kinds` and `logs` name the task (a row belongs when either matches; empty sets match
/// everything). Days are plain sections, never folded: a task's history is short.
/// `limit` shows whole days until that many runs are on screen, then a "Show All" row;
/// without a `limit` the newest 200 runs show and a "Show Older" row adds the rest (a
/// list that gains thousands of rows at once logs an AppKit warning). It reads
/// `ActivityModel.shared`, the model Activity itself uses: one refresh path.
struct RunHistoryList: View {
    var kinds: Set<JobKind> = []
    var logs: Set<EngineLog> = []
    var scope: ActivityScope = .all
    var query = ""
    var limit: Int?
    /// Shown when nothing matches; nil shows nothing (Activity has its own empty states).
    var emptyText: String? = "Nothing has run yet."
    /// False where the screen already refreshes the model itself (Activity).
    var refreshes = true
    /// False where the screen draws "Running Now" itself (Activity).
    var showsRunning = true

    /// Newest runs shown at once when there is no `limit`.
    private static let cap = 200

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    /// Runs added by each "Show Older" / "Show All" press, 200 at a time.
    @State private var extra = 0
    private var model: ActivityModel { .shared }

    /// Changes only when a job moves between queued, running and finished.
    private var storeStamp: [JobStamp] { store.jobs.map { JobStamp($0) } }

    private func belongs(_ row: ActivityRow) -> Bool {
        if kinds.isEmpty && logs.isEmpty { return true }
        return row.kind.map(kinds.contains) == true || row.log.map(logs.contains) == true
    }

    /// One day as shown: its own header numbers, and the rows that fit on screen.
    private struct ShownDay: Identifiable {
        let day: ActivityDay
        let rows: [ActivityRow]
        var id: String { day.id }
    }

    private func shownDays(of all: [ActivityDay]) -> (days: [ShownDay], cut: Bool) {
        let budget = (limit ?? Self.cap) + extra
        var days: [ShownDay] = []
        var used = 0
        for day in all {
            if used >= budget { return (days, true) }
            // a task's first screenful keeps whole days; once someone asks for more, pages go by rows
            if used + day.rows.count > budget && !days.isEmpty && limit != nil && extra == 0 { return (days, true) }
            let room = max(budget - used, 0)
            let rows = Array(day.rows.prefix(room))
            days.append(ShownDay(day: day, rows: rows))
            used += rows.count
            if rows.count < day.rows.count { return (days, true) }
        }
        return (days, false)
    }

    var body: some View {
        let actions = RunRowActions(store: store, navigator: navigator, model: model)
        let now = Date()
        let sections = model.sections(scope: scope, query: query)
        let all = sections.days
            .map { ActivityDay(day: $0.day, rows: $0.rows.filter(belongs)) }
            .filter { !$0.rows.isEmpty }
        let running = showsRunning ? sections.running.filter(belongs) : []
        let (days, cut) = shownDays(of: all)
        Group {
            if !running.isEmpty {
                Section("Running Now") {
                    ForEach(running) { actions.rowView($0, now: now) }
                }
            }
            if days.isEmpty, running.isEmpty, model.hasLoaded, let emptyText {
                Section { Text(emptyText).foregroundStyle(.secondary) }
            }
            ForEach(days) { shown in
                Section {
                    ForEach(shown.rows) { actions.rowView($0, now: now) }
                } header: {
                    // the whole day's numbers, even when only some of its rows are shown
                    Text("\(shown.day.title(now: now)) \(Text(shown.day.summary).font(.caption).foregroundStyle(.secondary))")
                }
            }
            if cut {
                Section {
                    Button(Names.Raw.showOlder) { extra += Self.cap }
                }
            }
        }
        .task { if refreshes { await model.refreshIfNeeded(store: store) } }
        .onChange(of: storeStamp) { if refreshes { Task { await model.refreshIfNeeded(store: store, maxAge: 0) } } }
    }
}

extension View {
    /// Put this on a `List` that holds run rows (`RunHistoryList`, Activity). A list estimates its
    /// rows at the system's default minimum height; when all its rows fit in the window (a short
    /// tab, a narrow search) AppKit kept that estimate for each row's drawing and cut the second
    /// line off every row. Telling the list how tall a two-line run row is, the native way
    /// (`defaultMinListRowHeight`), makes the estimate right.
    func runHistoryRows() -> some View {
        environment(\.defaultMinListRowHeight, 44)
    }
}
