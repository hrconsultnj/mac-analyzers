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

    /// How long a finished preview stays good enough to apply. The engine
    /// re-derives its findings at apply time, so the longer the gap the less the
    /// rows a person reviewed describe what would happen. The kernel enforces it
    /// (`apply(from:approved:)`), so a screen cannot forget to.
    public nonisolated static let reviewWindow: TimeInterval = 15 * 60

    // MARK: test hooks
    //
    // Everything marked `@_spi(TestSupport)` exists for `AgentRunner`'s probes and
    // `SnapshotRunner`'s fixtures, and only they import that interface. What the
    // attribute guarantees: code that does not write
    // `@_spi(TestSupport) import AnalyzersKit` cannot SEE these declarations, so
    // using one from the app, the screens or the menu is a compile error, and
    // `scripts/check.sh` fails if that import appears outside those two targets.
    // What it does NOT guarantee: the symbols are still compiled into the release
    // binary and can be reached by anything that links the module deliberately
    // (a debugger, a dlopen). It is a wall between our own targets, not a runtime
    // one.

    /// Every command runs this script instead of the engine's, with the
    /// arguments the kind built.
    @_spi(TestSupport) @ObservationIgnored public var scriptOverride: URL?

    /// The outcome a finished job reports, instead of reading the engine's real
    /// log (a fixture cannot write a block there).
    @_spi(TestSupport) @ObservationIgnored public var outcomeOverride: (@Sendable (JobKind, String?) -> JobOutcome)?

    /// Reads an installed schedule's script and arguments (`ScheduleKit` by
    /// default); a probe supplies its own plist.
    @_spi(TestSupport) @ObservationIgnored public var scheduleReader: (String) -> (script: String, arguments: [String])? =
        { ScheduleKit.scriptAndArguments(for: $0) }

    /// Previews and applies a person has dismissed (Discard, New preview, Try
    /// again). A screen never takes a dismissed job back when it reappears.
    public private(set) var dismissed: Set<UUID> = []

    /// The apply built from each preview. A preview is applied once: while its
    /// apply is waiting, running or has finished, a second `apply(from:)` is
    /// refused. An apply that failed or was stopped does not count, because the
    /// engine skips anything already gone, so applying the same reviewed list
    /// again can only finish what is left.
    @ObservationIgnored private var appliesByPreview: [UUID: Job] = [:]

    @ObservationIgnored private let ledger: JobLedger
    /// The clock the review window is measured on. The app's store always uses the real one.
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var processes: [UUID: EngineProcess] = [:]
    @ObservationIgnored private var cancelRequested: Set<UUID> = []
    /// Index lines on their way to disk, so a quit can wait for them.
    @ObservationIgnored private var ledgerWrites = 0

    public init(ledger: JobLedger = .standard) {
        self.ledger = ledger
        self.now = { Date() }
    }

    /// A store on a clock a probe controls, to show the review window without waiting for it.
    @_spi(TestSupport) public init(ledger: JobLedger, clock: @escaping () -> Date) {
        self.ledger = ledger
        self.now = clock
    }

    /// Marks a job as dismissed so screens stop re-adopting it.
    public func dismiss(_ job: Job?) {
        if let job { dismissed.insert(job.id) }
    }

    // MARK: - quitting

    /// A job is running or waiting: quitting the app would orphan the running
    /// one (its process tree outlives the app) and drop the waiting ones.
    public var hasWork: Bool { running != nil || !queued.isEmpty }

    /// "Stop and Quit": stops the running job's whole process tree and cancels
    /// the waiting ones, then waits (bounded) until every job has finished AND its
    /// index line is on disk, so Activity still says what became of them.
    /// Returns whether everything ended inside `timeout`.
    @discardableResult
    public func stopEverything(timeout: Duration = .seconds(8)) async -> Bool {
        for job in jobs where !job.state.isFinished { job.cancel() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if jobs.allSatisfy({ $0.state.isFinished }) && ledgerWrites == 0 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// "Quit and Let It Finish": the running job's tree is left running, so
    /// write its index line now (who started it, its banner so far) — otherwise
    /// the run could only ever read "Unknown". The waiting jobs will never start
    /// once the app is gone, so they are cancelled and recorded as such.
    public func recordRunningForQuit(timeout: Duration = .seconds(8)) async {
        let waiting = queued
        for job in waiting { job.cancel() }
        if let job = running {
            ledgerWrites += 1
            await ledger.append(job.ledgerEntry(finishedNow: true))
            ledgerWrites -= 1
        }
        // bounded like `stopEverything`: a write that never returns must not hold a quit for ever
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while ledgerWrites > 0, clock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
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
            // A cleaner runs by hand only as its own scheduled run ("Run Now"); what it
            // runs is read from the installed plist (`resolvedSchedule`), never from the caller.
            if case .schedule = trigger { return nil }
            return "\(kind.rawValue) cannot run without a review: only a scheduled run can be replayed."
        }
    }

    /// Why a scheduled run of `kind` for the agent `label` cannot be replayed, or
    /// nil when it can: the agent must be installed, and its plist must name the
    /// very script this app would run (the agent may have been installed from the
    /// other copy, the clone or the bundle).
    public func scheduleProblem(label: String, kind: JobKind) -> String? {
        guard let installed = scheduleReader(label) else { return "This schedule isn't installed on this Mac." }
        let theirs = URL(fileURLWithPath: installed.script).standardizedFileURL.path
        guard theirs == kind.script.standardizedFileURL.path else {
            return "The installed schedule runs a different copy of the cleaning script than this app would, so running it now would not do what the schedule does. Reinstall the background jobs from Setup."
        }
        return nil
    }

    /// For a cleaner `.run` triggered as `.schedule(label)`: the request with the
    /// installed plist's own arguments, whatever the caller put in the options.
    private func resolvedSchedule(_ request: JobRequest, trigger: JobTrigger) -> (JobRequest?, String?) {
        guard request.intent == .run, request.kind.isCleaner, case .schedule(let label) = trigger else {
            return (request, nil)
        }
        if let problem = scheduleProblem(label: label, kind: request.kind) { return (nil, problem) }
        guard let installed = scheduleReader(label) else { return (nil, "This schedule isn't installed on this Mac.") }
        var options = request.options
        options.scheduleArguments = installed.arguments
        return (JobRequest(kind: request.kind, intent: .run, options: options), nil)
    }

    // MARK: - making jobs

    /// Queues a job. A request the rules refuse comes back already `.failed`
    /// with the reason, and is never listed or run.
    @discardableResult
    public func enqueue(_ request: JobRequest, trigger: JobTrigger) -> Job {
        if let reason = Self.refusal(for: request, trigger: trigger) {
            return rejected(request, trigger: trigger, reason: reason)
        }
        let (resolved, problem) = resolvedSchedule(request, trigger: trigger)
        guard let resolved else { return rejected(request, trigger: trigger, reason: problem ?? "Not allowed.") }
        return add(resolved, trigger: trigger)
    }

    /// The only way to build a cleaner apply: from a finished preview, with the
    /// rows the user approved. The apply takes the preview's kind and options.
    ///
    /// Refused, with a sentence a person can read, when the preview finished more
    /// than `reviewWindow` ago or was dismissed (Discard): what was on screen is
    /// no longer what an apply would act on.
    @discardableResult
    public func apply(from preview: Job, approved: ApprovedSet) -> Job {
        let request = JobRequest(kind: preview.kind, intent: .apply, options: preview.request.options,
                                 approved: approved)
        let reason: String?
        if !preview.kind.isCleaner {
            reason = "\(preview.kind.rawValue) has no apply mode."
        } else if preview.intent != .preview {
            reason = "An apply must be built from a preview, not from a \(preview.intent.rawValue) job."
        } else if case .succeeded(let outcome) = preview.state {
            if case .newestFallback(let why) = outcome.match {
                reason = "\(why) There is nothing reviewed to apply, so preview again."
            } else if dismissed.contains(preview.id) {
                reason = "That review was discarded, so it can't be applied. Preview again to see what would be cleaned now."
            } else if let end = preview.finishedAt, now().timeIntervalSince(end) > Self.reviewWindow {
                reason = "That review is more than \(Int(Self.reviewWindow / 60)) minutes old, so it can no longer be applied. Preview again to see what would be cleaned now."
            } else if let prior = appliesByPreview[preview.id], prior.stillStands {
                reason = "This preview has already been applied — preview again to see what is left."
            } else {
                reason = preview.kind.takesReviewedList && approved.isUnrestricted
                    ? "\(preview.kind.rawValue) needs the exact list of reviewed items, so nothing that appeared after the review can be touched."
                    : nil
            }
        } else {
            reason = "The preview has not finished successfully, so there is nothing reviewed to apply."
        }
        if let reason { return rejected(request, trigger: .user, reason: reason) }
        let applied = add(request, trigger: .user)
        appliesByPreview[preview.id] = applied
        return applied
    }

    private func record(_ entry: JobLedgerEntry) {
        ledgerWrites += 1
        Task {
            await ledger.append(entry)
            ledgerWrites -= 1
        }
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
            record(job.ledgerEntry)
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
            final = .failed(JobFailure(
                message: request.kind.failureMessage(exitCode: failed, intent: request.intent,
                                                     options: request.options),
                exitCode: failed))
        } else {
            let kind = request.kind, header = job.runHeader, began = job.startedAt
            let override = outcomeOverride
            let outcome = await Task.detached {
                override?(kind, header) ?? RunMatcher.outcome(kind: kind, header: header, startedAt: began)
            }.value
            final = .succeeded(outcome)
        }
        await conclude(job, state: final, exitCode: stopped ? nil : code, approvedFile: approvedFile)
    }

    private func conclude(_ job: Job, state: Job.State, exitCode: Int32?, approvedFile: URL?) async {
        if let approvedFile { try? FileManager.default.removeItem(at: approvedFile) }
        cancelRequested.remove(job.id)
        job.finish(state, exitCode: exitCode)
        ledgerWrites += 1
        await ledger.append(job.ledgerEntry)
        ledgerWrites -= 1
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

private extension Job {
    /// An apply that is waiting, running or done uses its preview up; one that
    /// failed or was stopped does not.
    var stillStands: Bool {
        switch state {
        case .queued, .running, .succeeded: true
        case .failed, .cancelled: false
        }
    }
}
