import Foundation

/// One line of Activity: a run, whoever started it. Plain data — the table
/// shows it, the inspector explains it, and nothing here knows about views.
public struct ActivityRow: Identifiable, Sendable, Hashable {

    /// Where the row's facts came from. It decides what the inspector can do:
    /// only a live job has live output to follow and a Stop button.
    public enum Source: Sendable, Hashable {
        /// A job in the store: queued, running, or finished this session.
        case live(UUID)
        /// Only in the job index: a run the logs do not show (a failure before
        /// it logged, a stop, a report).
        case indexed(UUID)
        /// A block of an engine log, with the log's own index for it.
        case logged(EngineLog, runIndex: Int)
        /// A log that has no run yet, listed so every log still has a row.
        case emptyLog(EngineLog)
    }

    /// Who started it.
    public enum Trigger: String, Sendable, CaseIterable {
        case you = "You"
        case schedule = "Schedule"
        case guardian = "Guard"
        case terminal = "Terminal"
        case setup = "Setup"
        case update = "Update"
    }

    public enum Status: String, Sendable {
        case queued = "Queued"
        case running = "Running"
        case done = "Done"
        case failed = "Failed"
        case stopped = "Stopped"
        /// An empty log's placeholder row.
        case none = "No runs yet"
    }

    public let id: String
    public let source: Source
    /// The tracked job behind this row, whether it is still in the store, in
    /// the index, or both (a log block the index knows the starter of).
    public let jobID: UUID?
    public let title: String
    public let kind: JobKind?
    public let log: EngineLog?
    public let intent: JobIntent?
    public let started: Date?
    public let finished: Date?
    public let trigger: Trigger
    public let status: Status
    /// "Freed 4.2 GB", or why it did not finish.
    public let result: String
    /// The banner line the run printed, when known.
    public let header: String?
    /// A preview that found something and has not been followed by a newer run
    /// of the same task.
    public internal(set) var needsReview: Bool
    /// Items found by a preview (what `needsReview` is derived from).
    public let findings: Int

    public var isRunning: Bool { status == .running || status == .queued }
    public var isFailed: Bool { status == .failed }

    /// Seconds from start to finish; nil while it is still going or unknown.
    public var duration: TimeInterval? {
        guard let started, let finished else { return nil }
        return max(0, finished.timeIntervalSince(started))
    }

    /// What a "needs review" grouping and "newest per task" are keyed on.
    var taskKey: String { log?.rawValue ?? kind?.rawValue ?? id }
}

/// A job in the store, as plain values. Built on the main actor from a `Job`
/// (`Job.activitySnapshot`), so the join itself can run anywhere.
public struct LiveJobSnapshot: Sendable {
    public let id: UUID
    public let kind: JobKind
    public let intent: JobIntent
    public let trigger: JobTrigger
    public let status: ActivityRow.Status
    public let started: Date?
    public let finished: Date?
    public let runHeader: String?
    public let summary: ActivitySummary

    public init(id: UUID, kind: JobKind, intent: JobIntent, trigger: JobTrigger,
                status: ActivityRow.Status, started: Date?, finished: Date?,
                runHeader: String?, summary: ActivitySummary) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.trigger = trigger
        self.status = status
        self.started = started
        self.finished = finished
        self.runHeader = runHeader
        self.summary = summary
    }
}

public extension Job {
    @MainActor var activitySnapshot: LiveJobSnapshot {
        let status: ActivityRow.Status
        let summary: ActivitySummary
        switch state {
        case .queued:
            status = .queued
            summary = ActivitySummary("Waiting for the running job to finish")
        case .running:
            status = .running
            summary = ActivitySummary(step ?? "Working…")
        case .succeeded(let outcome):
            status = .done
            summary = ActivitySummary.of(outcome.parsed, kind: kind)
        case .failed(let failure):
            status = .failed
            summary = ActivitySummary.of(failure: failure)
        case .cancelled(let partial):
            status = .stopped
            summary = ActivitySummary.of(cancelledPartial: partial)
        }
        return LiveJobSnapshot(id: id, kind: kind, intent: intent, trigger: trigger, status: status,
                               started: startedAt, finished: finishedAt, runHeader: runHeader,
                               summary: summary)
    }
}
