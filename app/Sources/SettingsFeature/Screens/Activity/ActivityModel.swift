import AnalyzersKit
import Observation
import SwiftUI
import UIComponents

/// What Activity lists: every job in the store joined with the index of
/// app-started jobs and every engine log, so a run appears once (the rules
/// live in `ActivityJoin`). The model only reads the disk, runs the join off
/// the main actor, and hands the view finished rows.
///
/// Rows change when a job changes stage or the user refreshes — never on a
/// timer. A running job's elapsed time is drawn by the cell itself, so a tick
/// never reaches the table's data and never re-sorts it.
@MainActor @Observable
final class ActivityModel {

    private(set) var rows: [ActivityRow] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false

    @ObservationIgnored private var logRuns: [ActivityJoin.LogRuns] = []
    @ObservationIgnored private var generation = 0

    /// Reads the logs and the index again, then joins them with the store's
    /// jobs. A newer call supersedes an older one still in flight.
    func refresh(store: JobStore) async {
        generation += 1
        let mine = generation
        isLoading = true
        let live = store.jobs.map(\.activitySnapshot)
        let (logs, index) = await (Self.readLogs(), JobLedger.standard.entries())
        guard mine == generation else { return }
        let joined = await Task.detached(priority: .userInitiated) {
            ActivityJoin.rows(live: live, index: index, logs: logs,
                              titleForKind: { $0.title }, titleForLog: { $0.title })
        }.value
        guard mine == generation else { return }
        logRuns = logs
        rows = joined
        hasLoaded = true
        isLoading = false
    }

    private nonisolated static func readLogs() async -> [ActivityJoin.LogRuns] {
        await Task.detached(priority: .userInitiated) {
            EngineLog.allCases.map { ActivityJoin.LogRuns(log: $0, runs: LogParser.runs(for: $0)) }
        }.value
    }

    func row(forJob id: UUID) -> ActivityRow? { rows.first { $0.jobID == id } }

    /// The lines of a logged run, for a row that has no live job.
    func lines(for row: ActivityRow) -> [String] {
        guard case .logged(let log, let index) = row.source else { return [] }
        return logRuns.first { $0.log == log }?.runs.first { $0.id == index }?.lines ?? []
    }
}

// MARK: - what the table needs from a row

extension ActivityRow {
    /// Sort keys. Fixed values only: a running job's duration is not a key,
    /// or sorting by it would move rows on every tick.
    var startedSort: Date { started ?? (isRunning ? .distantFuture : .distantPast) }
    var durationSort: Double { duration ?? -1 }
    var triggerName: String { trigger.rawValue }
    var statusName: String { status.rawValue }

    var symbol: String { kind?.symbol ?? log?.symbol ?? "list.bullet.rectangle" }
    var tint: Color { kind?.tint ?? log?.tileColor ?? .gray }

    /// Where this row's task lives, as a deep-link target the router knows.
    var ownerTarget: String? {
        if let log { return "log:\(log.rawValue)" }
        switch kind {
        case .memoryReport, .storageReport: return "reports"
        case .networkSnapshot: return "network"
        case .installAgents, .sudoersInstall: return "setup"
        case .uninstallAgents: return "uninstall"
        default: return nil
        }
    }
}

/// Which rows the scope control shows.
enum ActivityScope: String, CaseIterable, Identifiable {
    case all, running, needsReview, failed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .running: "Running"
        case .needsReview: "Needs review"
        case .failed: "Failed"
        }
    }

    func includes(_ row: ActivityRow) -> Bool {
        switch self {
        case .all: true
        case .running: row.isRunning
        case .needsReview: row.needsReview
        case .failed: row.isFailed
        }
    }
}
