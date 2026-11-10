import Foundation

/// Builds Activity's rows: jobs in the store, the index of app-started jobs,
/// and every engine log, joined so a run is listed once.
///
/// History is derived, never copied (§4.5): the logs say what happened, the
/// index says who started it and what the logs cannot say (a failure before it
/// logged, a stop). The rules, in order:
///
///  1. A job in the store is a row. The index entry with its id, and the log
///     block carrying its banner, are the same run and add nothing.
///  2. A log block whose banner an index entry recorded is one row: the log's
///     words and numbers, the index's trigger, start and end.
///  3. Any other log block is a run nobody tracked. It is "Schedule" when it
///     falls within ten minutes of the agent's slot, otherwise "Terminal"
///     (the guard's and the watcher's logs are "Guard").
///  4. An index entry with no log block is listed from the index alone.
///  5. A log with no runs at all still gets one placeholder row.
public enum ActivityJoin {

    /// How close to an agent's slot a run must start to count as scheduled.
    public static let scheduleWindow: TimeInterval = 10 * 60

    /// One log's parsed blocks, newest first, as `LogParser.runs` returns them.
    public struct LogRuns: Sendable {
        public let log: EngineLog
        public let runs: [LogRun]
        public init(log: EngineLog, runs: [LogRun]) {
            self.log = log
            self.runs = runs
        }
    }

    /// When the agent that writes to `log` is due on `day`, one date per agent.
    public typealias Slots = @Sendable (_ log: EngineLog, _ day: Date) -> [Date]

    public static func rows(
        live: [LiveJobSnapshot],
        index: [JobLedgerEntry],
        logs: [LogRuns],
        slots: Slots = Self.installedSlots,
        titleForKind: (JobKind) -> String,
        titleForLog: (EngineLog) -> String
    ) -> [ActivityRow] {
        var rows: [ActivityRow] = []
        let liveIDs = Set(live.map(\.id))
        let liveHeaders = live.compactMap(\.runHeader)
        var usedIndex: Set<UUID> = []

        // 1. jobs in the store
        for job in live {
            rows.append(ActivityRow(
                id: job.id.uuidString, source: .live(job.id), jobID: job.id, title: titleForKind(job.kind),
                kind: job.kind, log: job.kind.log, intent: job.intent, started: job.started,
                finished: job.finished, trigger: trigger(of: job.trigger), status: job.status,
                result: job.summary.text, header: job.runHeader, needsReview: false,
                findings: job.summary.findings))
        }

        let indexByHeader = index.filter { !liveIDs.contains($0.id) && $0.runHeader != nil }

        // 2 and 3. every log block
        for source in logs {
            if source.runs.isEmpty {
                rows.append(placeholder(for: source.log, title: titleForLog(source.log)))
                continue
            }
            for run in source.runs {
                if liveHeaders.contains(where: { RunMatcher.matches(run, header: $0) }) { continue }
                let entry = indexByHeader.first { RunMatcher.matches(run, header: $0.runHeader ?? "") }
                if let entry { usedIndex.insert(entry.id) }
                rows.append(loggedRow(run, in: source.log, entry: entry,
                                      title: titleForLog(source.log), slots: slots))
            }
        }

        // 4. index-only entries
        for entry in index where !liveIDs.contains(entry.id) && !usedIndex.contains(entry.id) {
            rows.append(indexedRow(entry, title: titleForKind(entry.kind)))
        }

        markNeedsReview(&rows)
        return rows
    }

    // MARK: - rows

    private static func loggedRow(_ run: LogRun, in log: EngineLog, entry: JobLedgerEntry?,
                                  title: String, slots: Slots) -> ActivityRow {
        let summary = ActivitySummary.of(run, in: log)
        let date = headerDate(run.header)
        let status: ActivityRow.Status
        var result = summary.text
        var findings = summary.findings
        if let entry, entry.cancelled {
            status = .stopped
            result = "Stopped"
            findings = 0
        } else if let entry, let code = entry.exit, code != 0 {
            status = .failed
            result = ExitExplanation.explain(exitCode: code, verb: verb(entry.intent))
            findings = 0
        } else {
            status = .done
        }
        let who: ActivityRow.Trigger = entry.map { trigger(of: $0.trigger) }
            ?? inferred(log: log, at: date, slots: slots)
        return ActivityRow(
            id: "log:\(log.rawValue):\(run.id):\(run.header)", source: .logged(log, runIndex: run.id),
            jobID: entry?.id, title: title, kind: entry?.kind, log: log,
            intent: entry?.intent ?? intent(of: run.header),
            started: entry?.start ?? date, finished: entry?.end, trigger: who, status: status,
            result: result, header: run.header, needsReview: false, findings: findings)
    }

    private static func indexedRow(_ entry: JobLedgerEntry, title: String) -> ActivityRow {
        let status: ActivityRow.Status
        let result: String
        if entry.cancelled {
            status = .stopped
            result = "Stopped"
        } else if let code = entry.exit, code != 0 {
            status = .failed
            result = ExitExplanation.explain(exitCode: code, verb: verb(entry.intent))
        } else {
            status = .done
            result = ActivitySummary.of(.none, kind: entry.kind).text
        }
        return ActivityRow(
            id: "index:\(entry.id.uuidString)", source: .indexed(entry.id), jobID: entry.id, title: title,
            kind: entry.kind, log: entry.kind.log, intent: entry.intent, started: entry.start,
            finished: entry.end, trigger: trigger(of: entry.trigger), status: status, result: result,
            header: entry.runHeader, needsReview: false, findings: 0)
    }

    private static func placeholder(for log: EngineLog, title: String) -> ActivityRow {
        ActivityRow(id: "empty:\(log.rawValue)", source: .emptyLog(log), jobID: nil, title: title, kind: nil,
                    log: log, intent: nil, started: nil, finished: nil, trigger: owner(of: log) ?? .terminal,
                    status: .none, result: "Nothing logged yet", header: nil, needsReview: false,
                    findings: 0)
    }

    // MARK: - needs review

    /// The newest run of each task, when it is a preview that found something.
    /// Older previews are history, not a to-do.
    private static func markNeedsReview(_ rows: inout [ActivityRow]) {
        var newest: [String: Int] = [:]
        for (position, row) in rows.enumerated() where row.status == .done {
            guard let when = row.finished ?? row.started else { continue }
            if let current = newest[row.taskKey],
               let existing = rows[current].finished ?? rows[current].started, existing >= when { continue }
            newest[row.taskKey] = position
        }
        for position in newest.values where rows[position].intent == .preview && rows[position].findings > 0 {
            rows[position].needsReview = true
        }
    }

    // MARK: - small decisions

    static func trigger(of job: JobTrigger) -> ActivityRow.Trigger {
        switch job {
        case .user: .you
        case .schedule: .schedule
        case .setup: .setup
        case .update: .update
        }
    }

    /// The index's spelling: `user`, `schedule:<label>`, `setup`, `update`.
    static func trigger(of label: String) -> ActivityRow.Trigger {
        if label.hasPrefix("schedule") { return .schedule }
        switch label {
        case "setup": return .setup
        case "update": return .update
        default: return .you
        }
    }

    /// Logs one background program owns outright.
    private static func owner(of log: EngineLog) -> ActivityRow.Trigger? {
        switch log {
        case .guardLog, .forensics, .persistence: .guardian
        default: nil
        }
    }

    private static func inferred(log: EngineLog, at date: Date?, slots: Slots) -> ActivityRow.Trigger {
        if let owner = owner(of: log) { return owner }
        guard let date else { return .terminal }
        let due = slots(log, date)
        return due.contains { abs($0.timeIntervalSince(date)) <= scheduleWindow } ? .schedule : .terminal
    }

    private static func verb(_ intent: JobIntent) -> String {
        switch intent {
        case .preview: "preview"
        case .apply: "apply"
        case .run: "run it"
        }
    }

    /// A banner without "DRY RUN" is an action.
    private static func intent(of header: String) -> JobIntent? {
        let text = header.uppercased()
        if text.contains("DRY RUN") || text.contains("DRY-RUN") { return .preview }
        if text.contains("APPLY") { return .apply }
        return nil
    }

    /// The first `YYYY-MM-DD HH:MM[:SS]` in a run's banner, in the local zone.
    static func headerDate(_ header: String) -> Date? {
        guard let match = header.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/)
        else { return nil }
        var parts = DateComponents()
        parts.year = Int(match.1)
        parts.month = Int(match.2)
        parts.day = Int(match.3)
        parts.hour = Int(match.4)
        parts.minute = Int(match.5)
        parts.second = match.6.flatMap { Int($0) } ?? 0
        return Calendar.current.date(from: parts)
    }

    // MARK: - the installed schedule

    /// The agents' labels per log: the logs a launchd job writes.
    static func agentLabels(for log: EngineLog) -> [String] {
        switch log {
        case .memoryClean: ["com.mac-analyzers.memory-autoclean.daily"]
        case .storageClean: ["com.mac-analyzers.storage-autoclean.daily", "com.mac-analyzers.storage-autoclean.deep"]
        default: []
        }
    }

    /// Slots from the installed plists: the daily agents' hour and minute on
    /// the run's own day. An interval agent has no fixed slot to compare with.
    @Sendable public static func installedSlots(for log: EngineLog, on day: Date) -> [Date] {
        agentLabels(for: log).compactMap { label in
            guard case .daily(let hour, let minute)? = ScheduleKit.schedule(for: label) else { return nil }
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
    }
}
