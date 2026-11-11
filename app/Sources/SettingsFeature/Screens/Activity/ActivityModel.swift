import AnalyzersKit
import Observation
import SwiftUI
import UIComponents

/// What Activity lists: every job in the store joined with the index of
/// app-started jobs and every engine log, so a run appears once (the rules
/// live in `ActivityJoin`). The model reads the disk, runs the join off the
/// main actor, and hands the view finished rows.
///
/// Rows change when a job changes stage or the user refreshes — never on a
/// timer. A running job's elapsed time is drawn by the cell itself, so a tick
/// never reaches the list's data.
@MainActor @Observable
final class ActivityModel {

    /// The one model every view of runs reads: Activity, a task screen's run
    /// history and the run screens. One refresh path, so opening a screen that
    /// shows runs does not read every log again behind another's back.
    static let shared = ActivityModel()

    private(set) var rows: [ActivityRow] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false

    @ObservationIgnored private var logRuns: [ActivityJoin.LogRuns] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshedAt: Date = .distantPast
    /// The refresh running now: a screen that appears meanwhile awaits it instead of starting its own.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    /// A job changed stage while a refresh was running: it must read once more.
    @ObservationIgnored private var dirty = false

    /// Refreshes unless the rows were read a moment ago. For screens that merely
    /// show runs when they appear; a job changing stage calls `refresh` itself.
    /// `maxAge: 0` is for a job changing stage: it always reads, and one that arrives
    /// while a read is running makes that read go round once more instead of starting a
    /// second one beside it.
    func refreshIfNeeded(store: JobStore, maxAge: TimeInterval = 5) async {
        if maxAge == 0 { dirty = true }
        if let inFlight { await inFlight.value; return }
        guard !hasLoaded || Date().timeIntervalSince(refreshedAt) >= maxAge else { return }
        // `inFlight` is cleared inside the task, in the same step as the last `dirty` check: a
        // change that arrives after that sees no read running and starts its own
        let task = Task {
            repeat {
                dirty = false
                await refresh(store: store)
            } while dirty
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// Reads the logs and the index again, then joins them with the store's
    /// jobs. A newer call supersedes an older one still in flight.
    func refresh(store: JobStore) async {
        generation += 1
        let mine = generation
        isLoading = true
        let live = store.jobs.map(\.activitySnapshot)
        let dismissed = store.dismissed
        let (logs, index) = await (Self.readLogs(), JobLedger.standard.entries())
        guard mine == generation else { return }
        let joined = await Task.detached(priority: .userInitiated) {
            ActivityJoin.rows(live: live, index: index, logs: logs, dismissed: dismissed,
                              titleForKind: { $0.title }, titleForLog: { $0.activityTitle })
        }.value
        guard mine == generation else { return }
        logRuns = logs
        rows = joined
        refreshedAt = Date()
        hasLoaded = true
        isLoading = false
    }

    private nonisolated static func readLogs() async -> [ActivityJoin.LogRuns] {
        await Task.detached(priority: .userInitiated) { ActivityJoin.readLogs() }.value
    }

    // MARK: - finding a row again

    /// When the soonest "waiting for review" row stops being so.
    var nextReviewExpiry: Date? {
        rows.filter(\.needsReview).compactMap { $0.finished }
            .map { $0.addingTimeInterval(JobStore.reviewWindow) }.min()
    }

    func row(forJob id: UUID) -> ActivityRow? { rows.first { $0.jobID == id } }

    /// The row a route names: a log, a banner and which of the identical banners.
    func row(for reference: RunReference) -> ActivityRow? {
        rows.first {
            guard case .logged(let log, let header, let ordinal) = $0.source else { return false }
            return log == reference.log && header == reference.header && ordinal == reference.ordinal
        }
    }

    /// The log block behind a logged row.
    func logRun(for row: ActivityRow) -> LogRun? {
        guard case .logged(let log, let header, let ordinal) = row.source else { return nil }
        return logRun(for: RunReference(log: log, header: header, ordinal: ordinal))
    }

    /// The log block a reference names, or nil once the log has moved on.
    func logRun(for reference: RunReference) -> LogRun? {
        logRuns.first { $0.log == reference.log }.flatMap { reference.resolve(in: $0.runs) }
    }

    /// Whether the log's window may have cut this block off: it is the oldest
    /// block read, and the log is longer than the window.
    func cutByWindow(_ run: LogRun, of row: ActivityRow) -> Bool {
        guard case .logged(let log, _, _) = row.source,
              let runs = logRuns.first(where: { $0.log == log })?.runs,
              runs.last?.id == run.id, runs.count > 0,
              let size = log.url.flatMap({ try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? UInt64 })
        else { return false }
        return size > 262_144
    }

    func lines(for row: ActivityRow) -> [String] { logRun(for: row)?.lines ?? [] }

    // MARK: - the screen's sections

    /// The rows the scope and search leave, grouped.
    func sections(scope: ActivityScope, query: String) -> ActivitySections {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = rows.filter { row in
            guard scope.includes(row) || (scope == .all) else { return false }
            guard !needle.isEmpty else { return true }
            return row.displayTitle.lowercased().contains(needle) || row.line.lowercased().contains(needle)
                || row.trigger.rawValue.lowercased().contains(needle)
        }
        var grouped = ActivityGrouping.sections(matching)
        if scope != .all {
            // "Hasn't run yet" is the whole picture, not a filter result
            grouped = ActivitySections(running: grouped.running, days: grouped.days, neverRan: [])
        }
        return grouped
    }
}
