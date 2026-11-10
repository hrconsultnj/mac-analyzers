import Foundation
import Observation

/// The one place jobs are made and run.
///
/// - One engine lane: the scripts sweep the same disk and process table and
///   six hold single-instance locks, so jobs queue and run one at a time.
/// - A cleaner can only be applied from a finished preview of the same kind
///   and options: `enqueue` refuses `.apply`, and `apply(from:approved:)`
///   is the only way to build one.
@MainActor @Observable
public final class JobStore {

    /// Oldest first. Finished jobs are kept for the life of the app, up to `keepFinished`.
    public private(set) var jobs: [Job] = []
    public var running: Job? { jobs.first { $0.state.isRunning } }
    public var queued: [Job] { jobs.filter { $0.state.isQueued } }

    static let keepFinished = 200

    /// Test hook, used only by `agent-runner --probe-job-script`: every command
    /// runs this script instead of the engine's, with the arguments the kind
    /// built. The app never sets it.
    @ObservationIgnored public var scriptOverride: URL?

    @ObservationIgnored private let ledger: JobLedger
    @ObservationIgnored private var processes: [UUID: EngineProcess] = [:]
    @ObservationIgnored private var cancelRequested: Set<UUID> = []

    public init(ledger: JobLedger = .standard) {
        self.ledger = ledger
    }

    // MARK: - the rules

    /// Why this request may not be queued directly, or nil when it may.
    public static func refusal(for request: JobRequest, trigger: JobTrigger) -> String? {
        let kind = request.kind
        switch request.intent {
        case .apply:
            return kind.isCleaner
                ? "\(kind.rawValue) cannot be applied directly: an apply needs a finished preview of the same options. Use JobStore.apply(from:approved:)."
                : "\(kind.rawValue) has no apply mode."
        case .preview:
            return kind.isCleaner ? nil : "\(kind.rawValue) has no preview mode."
        case .run:
            guard kind.isCleaner else { return nil }
            // A cleaner runs by hand only as its own scheduled run ("Run now"),
            // whose arguments come from the installed plist.
            if case .schedule = trigger, request.options.scheduleArguments != nil { return nil }
            return "\(kind.rawValue) cannot run without a review: only a scheduled run can be replayed."
        }
    }

    // MARK: - making jobs

    /// Queues a job. A request the rules refuse comes back already `.failed`
    /// with the reason, and is never listed or run.
    @discardableResult
    public func enqueue(_ request: JobRequest, trigger: JobTrigger) -> Job {
        if let reason = Self.refusal(for: request, trigger: trigger) {
            return rejected(request, trigger: trigger, reason: reason)
        }
        return add(request, trigger: trigger)
    }

    /// The only way to build a cleaner apply: from a finished preview, with the
    /// rows the user approved. The apply takes the preview's kind and options.
    @discardableResult
    public func apply(from preview: Job, approved: ApprovedSet) -> Job {
        let request = JobRequest(kind: preview.kind, intent: .apply, options: preview.request.options,
                                 approved: approved)
        let reason: String?
        if !preview.kind.isCleaner {
            reason = "\(preview.kind.rawValue) has no apply mode."
        } else if preview.intent != .preview {
            reason = "An apply must be built from a preview, not from a \(preview.intent.rawValue) job."
        } else if case .succeeded = preview.state {
            reason = preview.kind.alwaysSendsApprovalList && approved.isUnrestricted
                ? "\(preview.kind.rawValue) needs the exact list of approved items."
                : nil
        } else {
            reason = "The preview has not finished successfully, so there is nothing reviewed to apply."
        }
        if let reason { return rejected(request, trigger: .user, reason: reason) }
        return add(request, trigger: .user)
    }

    private func rejected(_ request: JobRequest, trigger: JobTrigger, reason: String) -> Job {
        let job = Job(request: request, trigger: trigger)
        job.finish(.failed(JobFailure(message: reason, exitCode: nil)), exitCode: nil)
        return job
    }

    private func add(_ request: JobRequest, trigger: JobTrigger) -> Job {
        let job = Job(request: request, trigger: trigger)
        job.cancelAction = { [weak self] job in self?.cancel(job) }
        jobs.append(job)
        pump()
        return job
    }

    // MARK: - the lane

    private func pump() {
        guard running == nil, let next = queued.first else { return }
        next.markRunning()
        Task { await self.execute(next) }
    }

    private func cancel(_ job: Job) {
        switch job.state {
        case .queued:
            job.finish(.cancelled(partial: false), exitCode: nil)
            let entry = job.ledgerEntry
            Task { await ledger.append(entry) }
        case .running:
            cancelRequested.insert(job.id)
            processes[job.id]?.cancel()
        default:
            break
        }
    }

    private func execute(_ job: Job) async {
        let request = job.request
        var approvedFile: URL?
        let commands: [EngineCommand]
        do {
            // A list that cannot be written must stop the apply, never widen it
            // to "everything".
            approvedFile = try request.approved?.writeFile(for: request.kind)
            commands = try request.kind.commands(intent: request.intent, options: request.options,
                                                 approvedFile: approvedFile)
                .map { command in scriptOverride.map { EngineCommand(script: $0, args: command.args) } ?? command }
        } catch {
            await conclude(job, state: .failed(JobFailure(message: "\(error)", exitCode: nil)),
                           exitCode: nil, approvedFile: approvedFile)
            return
        }

        var firstFailure: Int32?
        var stopped = false
        var ranAny = false
        for command in commands {
            if cancelRequested.contains(job.id) { stopped = true; break }
            let process = EngineProcess(script: command.script, args: command.args)
            processes[job.id] = process
            let result = await process.run { [job] batch in await job.receive(batch) }
            processes[job.id] = nil
            ranAny = ranAny || result.launched
            if result.wasCancelled && (result.exitCode != 0 || result.killedBySignal) {
                stopped = true
                break
            }
            if result.exitCode != 0, firstFailure == nil { firstFailure = result.exitCode }
        }

        let final: Job.State
        let code = firstFailure ?? 0
        if stopped {
            let partial = ranAny && (request.intent == .apply || (request.intent == .run && request.kind.isCleaner))
            final = .cancelled(partial: partial)
        } else if let failed = firstFailure {
            let verb = request.intent == .preview ? "preview" : request.intent == .apply ? "apply" : "run it"
            final = .failed(JobFailure(message: ExitExplanation.explain(exitCode: failed, verb: verb),
                                       exitCode: failed))
        } else {
            let kind = request.kind, header = job.runHeader
            let outcome = await Task.detached { RunMatcher.outcome(kind: kind, header: header) }.value
            final = .succeeded(outcome)
        }
        await conclude(job, state: final, exitCode: stopped ? nil : code, approvedFile: approvedFile)
    }

    private func conclude(_ job: Job, state: Job.State, exitCode: Int32?, approvedFile: URL?) async {
        if let approvedFile { try? FileManager.default.removeItem(at: approvedFile) }
        cancelRequested.remove(job.id)
        job.finish(state, exitCode: exitCode)
        await ledger.append(job.ledgerEntry)
        trimFinished()
        pump()
    }

    private func trimFinished() {
        let finished = jobs.filter { $0.state.isFinished }
        guard finished.count > Self.keepFinished else { return }
        let drop = Set(finished.prefix(finished.count - Self.keepFinished).map(\.id))
        jobs.removeAll { drop.contains($0.id) }
    }
}

extension Job.State {
    var isRunning: Bool { if case .running = self { true } else { false } }
    var isQueued: Bool { if case .queued = self { true } else { false } }
}
