import Foundation
import Observation

/// Who started a job.
public enum JobTrigger: Sendable, Hashable {
    case user
    case schedule(String)
    case setup
    case update

    /// `user`, `schedule:<label>`, `setup`, `update` — the ledger's spelling.
    public var ledgerLabel: String {
        switch self {
        case .user: "user"
        case .schedule(let label): "schedule:\(label)"
        case .setup: "setup"
        case .update: "update"
        }
    }
}

/// A request to run something through the engine. Building one grants
/// nothing: `JobStore` decides whether it may run (see `JobStore.refusal`).
public struct JobRequest: Sendable {
    public let kind: JobKind
    public let intent: JobIntent
    public let options: JobOptions
    /// Present only on an apply built by `JobStore.apply(from:approved:)`.
    public let approved: ApprovedSet?

    public init(kind: JobKind, intent: JobIntent, options: JobOptions = JobOptions(),
                approved: ApprovedSet? = nil) {
        self.kind = kind
        self.intent = intent
        self.options = options
        self.approved = approved
    }
}

/// Why a job did not finish, in words a person can read.
public struct JobFailure: Sendable {
    public let message: String
    /// The script's exit code, when it ran far enough to have one.
    public let exitCode: Int32?
}

/// One tracked run: queued, running, then finished. Created only by `JobStore`.
@MainActor @Observable
public final class Job: Identifiable {

    public enum State {
        case queued
        case running
        case succeeded(JobOutcome)
        case failed(JobFailure)
        /// `partial` is true when an apply was stopped part-way, so some items
        /// were already handled.
        case cancelled(partial: Bool)

        public var isFinished: Bool {
            switch self {
            case .queued, .running: false
            default: true
            }
        }
    }

    /// The most lines kept; older ones are dropped. `receivedLineCount` still counts them.
    public static let ringCapacity = 2_000

    public nonisolated let id = UUID()
    public let request: JobRequest
    public let trigger: JobTrigger

    public private(set) var state: State = .queued
    /// The last 2,000 lines of output, oldest first.
    public private(set) var lines: [String] = []
    /// Every line ever received, including those the ring dropped. The number
    /// of the first line in `lines` is `receivedLineCount - lines.count`.
    public private(set) var receivedLineCount = 0
    /// The last `### ` group line, without the marker: "Checking build caches…".
    public private(set) var step: String?
    public private(set) var startedAt: Date?
    public private(set) var finishedAt: Date?
    /// The first run banner this job's own stdout printed. `RunMatcher` finds
    /// the log block that carries it.
    public private(set) var runHeader: String?
    public private(set) var exitCode: Int32?
    /// Set when the outcome had to be guessed.
    public var note: String? {
        if case .succeeded(let outcome) = state { outcome.note } else { nil }
    }

    @ObservationIgnored var cancelAction: (@MainActor (Job) -> Void)?

    init(request: JobRequest, trigger: JobTrigger) {
        self.request = request
        self.trigger = trigger
    }

    public var kind: JobKind { request.kind }
    public var intent: JobIntent { request.intent }

    /// Stops it. Queued: it never starts. Running: the whole process tree is
    /// stopped (leaf-first SIGTERM, SIGKILL after five seconds).
    public func cancel() { cancelAction?(self) }

    // MARK: - driven by JobStore

    func markRunning() {
        state = .running
        startedAt = Date()
    }

    func receive(_ batch: [String]) {
        for line in batch {
            if runHeader == nil, let banner = RunMatcher.banner(in: line) { runHeader = banner }
            if line.hasPrefix("### ") {
                step = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
        }
        receivedLineCount += batch.count
        lines.append(contentsOf: batch)
        if lines.count > Self.ringCapacity { lines.removeFirst(lines.count - Self.ringCapacity) }
    }

    func finish(_ final: State, exitCode: Int32?) {
        self.exitCode = exitCode
        finishedAt = Date()
        state = final
    }

    /// The index line for a job the app is leaving running: not finished, not
    /// cancelled, no exit code, ending "now" as far as the app can tell.
    func ledgerEntry(finishedNow: Bool) -> JobLedgerEntry {
        JobLedgerEntry(id: id, kind: kind, intent: intent, trigger: trigger.ledgerLabel,
                       start: startedAt, end: Date(), exit: nil, cancelled: false, runHeader: runHeader)
    }

    var ledgerEntry: JobLedgerEntry {
        var wasCancelled = false
        if case .cancelled = state { wasCancelled = true }
        return JobLedgerEntry(id: id, kind: kind, intent: intent, trigger: trigger.ledgerLabel,
                              start: startedAt, end: finishedAt ?? Date(), exit: exitCode,
                              cancelled: wasCancelled, runHeader: runHeader)
    }
}
