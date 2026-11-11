import Foundation

/// One entry of Activity: a run, whoever started it. Plain data — the list
/// shows it, the run screen explains it, and nothing here knows about views.
public struct ActivityRow: Identifiable, Sendable, Hashable {

    /// Where the row's facts came from. It decides what the run screen can do:
    /// only a live job has live output to follow and a Stop button.
    public enum Source: Sendable, Hashable {
        /// A job in the store: queued, running, or finished this session.
        case live(UUID)
        /// Only in the job index: a run the logs do not show (a failure before
        /// it logged, a stop, a report).
        case indexed(UUID)
        /// A block of an engine log. The header and its ordinal (the nth block
        /// with that identical header, oldest first) name it for good: unlike a
        /// position in the file, neither moves when the log grows.
        case logged(EngineLog, header: String, ordinal: Int)
        /// A log that has no run yet.
        case emptyLog(EngineLog)
        /// A task that leaves no log the app reads (a report, a snapshot) and
        /// has not run.
        case neverRan(JobKind)
    }

    /// Who started it. `unknown` is the honest answer when nothing in the run
    /// says: it is never guessed as Terminal.
    public enum Trigger: String, Sendable, CaseIterable {
        case you = "You"
        case schedule = "Schedule"
        case guardian = "Guard"
        case terminal = "Terminal"
        case unknown = "Unknown"
        case setup = "Setup"
        case update = "Update"
    }

    public enum Status: String, Sendable {
        case queued = "Queued"
        case running = "Running"
        case done = "Done"
        case failed = "Failed"
        case stopped = "Stopped"
        /// A task with no run yet.
        case none = "No runs yet"
    }

    public let id: String
    public let source: Source
    /// The tracked job behind this row, whether it is still in the store, in
    /// the index, or both (a log block the index knows the starter of).
    public let jobID: UUID?
    /// The task's own name ("Storage Clean"). The list adds the mode.
    public let title: String
    public let kind: JobKind?
    public let log: EngineLog?
    public let intent: JobIntent?
    /// "Daily" or "Deep" for the storage cleaner; nil where a task has no flavours.
    public let flavor: String?
    public let started: Date?
    public let finished: Date?
    public let trigger: Trigger
    public let status: Status
    /// "Freed 4.2 GB", or why it did not finish.
    public let result: String
    /// What to say instead while a preview is waiting for a decision.
    public let reviewResult: String?
    /// The banner line the run printed, when known.
    public let header: String?
    /// A recent preview that found something and has not been followed by a
    /// newer run of the same task.
    public internal(set) var needsReview: Bool
    /// Items found by a preview (what `needsReview` is derived from).
    public let findings: Int
    /// Disk space this run gave back, and (separately) the memory of the
    /// processes it closed; what a day's totals add up.
    public let freedBytes: Int64
    public let memoryBytes: Int64
    public let closed: Int

    /// What "the newest run of this task" is keyed on: the log a task writes,
    /// or its kind where it writes none.
    var taskKey: String { log?.rawValue ?? kind?.rawValue ?? id }

    /// A restore from Undo, listed from its own block in a cleaner's log. It is not a run of
    /// that cleaner: it never replaces a waiting preview, and it has nothing to apply.
    public var isRestore: Bool { header.map(RestoreBlock.isRestore(header:)) ?? false }

    public var isRunning: Bool { status == .running || status == .queued }
    public var isFailed: Bool { status == .failed }

    /// Seconds from start to finish; nil while it is still going or unknown.
    public var duration: TimeInterval? {
        guard let started, let finished else { return nil }
        return max(0, finished.timeIntervalSince(started))
    }

    /// The kind of run, where it matters, as its own short words: "Deep cleanup preview",
    /// "Memory report", "Audit". nil for a task with no flavours. The list shows it beside the task's
    /// name as secondary text; it is never glued into the title.
    public var kindOfRun: String? {
        var mode: [String] = []
        switch kind {
        case .reclaim: mode.append("reclaim")
        case .storageClean: if let flavor { mode.append("\(flavor.lowercased()) cleanup") }
        case .memoryReport: mode.append("memory report")
        case .storageReport: mode.append("storage report")
        case .installAgents: mode.append("install background jobs")
        case .uninstallAgents: mode.append("turn off background jobs")
        case .eject: mode.append("eject disk image")
        default: break
        }
        if let kind, kind.isCleaner {
            let audit = kind == .spotlight || kind == .loginItems
            switch intent {
            case .preview: mode.append(audit ? "audit" : "preview")
            case .apply: if audit { mode.append(kind == .spotlight ? "fencing" : "cleanup") }
            default: break
            }
        }
        guard !mode.isEmpty else { return nil }
        let words = mode.joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The task and its kind of run as ONE plain string, for places that need text rather than
    /// two fields (search, copy, the probe): "Caches & Builds — deep cleanup preview".
    public var displayTitle: String {
        kindOfRun.map { "\(title) — \($0.prefix(1).lowercased() + $0.dropFirst())" } ?? title
    }

    /// The line a person reads: the waiting-preview wording when a decision is due.
    public var line: String { needsReview ? (reviewResult ?? result) : result }

    /// Whether a person started a task or a program wrote an event: guard days,
    /// crisis reports and startup changes are things that happened, not runs.
    public var isEventLog: Bool {
        guard let log else { return false }
        switch log {
        case .guardLog, .persistence, .forensics: return true
        default: return false
        }
    }
}

/// A job in the store, as plain values. Built on the main actor from a `Job`
/// (`Job.activitySnapshot`), so the join itself can run anywhere.
public struct LiveJobSnapshot: Sendable {
    public let id: UUID
    public let kind: JobKind
    public let intent: JobIntent
    public let options: JobOptions
    public let trigger: JobTrigger
    public let status: ActivityRow.Status
    public let started: Date?
    public let finished: Date?
    public let runHeader: String?
    public let summary: ActivitySummary

    public init(id: UUID, kind: JobKind, intent: JobIntent, options: JobOptions = JobOptions(),
                trigger: JobTrigger, status: ActivityRow.Status, started: Date?, finished: Date?,
                runHeader: String?, summary: ActivitySummary) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.options = options
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
            if case .newestFallback = outcome.match {
                // This job's own block was not in the log: the newest block is somebody
                // else's run, so none of its numbers are said here.
                summary = ActivitySummary("Finished — this run's own results couldn't be found in the log")
            } else {
                summary = ActivitySummary.of(outcome.parsed, kind: kind)
            }
        case .failed(let failure):
            status = .failed
            summary = ActivitySummary.of(failure: failure)
        case .cancelled(let partial):
            status = .stopped
            summary = ActivitySummary.of(cancelledPartial: partial)
        }
        return LiveJobSnapshot(id: id, kind: kind, intent: intent, options: request.options,
                               trigger: trigger, status: status, started: startedAt,
                               finished: finishedAt, runHeader: runHeader, summary: summary)
    }
}
