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
///  3. Any other log block is a run nobody tracked. Who started it is read from
///     what the run itself says (see `attribute`) and is "Unknown" when it says
///     nothing — never guessed.
///  4. An index entry with no log block is listed from the index alone.
///  5. A task with no run at all gets one placeholder row, which the screen
///     shows under "Hasn't run yet".
///
/// A logged row's id is the log, the block's banner and the ordinal of that
/// banner (the nth identical one, oldest first). A position in the file would
/// shift whenever the log grows past the parser's window.
public enum ActivityJoin {

    /// How close to an agent's slot a run must start to count as scheduled.
    public static let scheduleWindow: TimeInterval = 10 * 60

    /// The flags the memory guard gives `memory-auto-clean.sh` when it calls it
    /// (documented in `memory-guard.sh`).
    static let guardFlags = ["--apply", "--dev", "--quiet"]

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
    /// The arguments (after the script) each installed agent of `log` passes.
    public typealias AgentArguments = @Sendable (_ log: EngineLog) -> [[String]]

    public static func rows(
        live: [LiveJobSnapshot],
        index: [JobLedgerEntry],
        logs: [LogRuns],
        now: Date = Date(),
        dismissed: Set<UUID> = [],
        slots: Slots = Self.installedSlots,
        agentArguments: AgentArguments = Self.installedArguments,
        modified: (EngineLog) -> Date? = { $0.url.flatMap(AnalyzersPaths.modificationDate) },
        hasOutput: (JobKind) -> Bool = Self.hasOutput,
        titleForKind: (JobKind) -> String,
        titleForLog: (EngineLog) -> String
    ) -> [ActivityRow] {
        var rows: [ActivityRow] = []
        let liveIDs = Set(live.map(\.id))
        let liveHeaders = live.compactMap(\.runHeader)
        var usedIndex: Set<UUID> = []

        // 1. jobs in the store
        for job in live {
            let flavor = flavor(header: job.runHeader, options: job.options, kind: job.kind)
            rows.append(ActivityRow(
                id: job.id.uuidString, source: .live(job.id), jobID: job.id, title: titleForKind(job.kind),
                kind: job.kind, log: job.kind.log, intent: job.intent, flavor: flavor, started: job.started,
                finished: job.finished, trigger: trigger(of: job.trigger), status: job.status,
                result: job.summary.text, reviewResult: job.summary.reviewText, header: job.runHeader,
                needsReview: false, findings: job.summary.findings, freedBytes: job.summary.freedBytes,
                memoryBytes: job.summary.memoryBytes, closed: job.summary.closed))
        }

        let indexByHeader = index.filter { !liveIDs.contains($0.id) && $0.runHeader != nil }

        // 2 and 3. every log block
        for source in logs {
            if source.runs.isEmpty {
                rows.append(placeholder(for: source.log, title: titleForLog(source.log)))
                continue
            }
            for (position, run) in source.runs.enumerated() {
                if liveHeaders.contains(where: { RunMatcher.matches(run, header: $0) }) { continue }
                // A block with no banner is the tail of a run the parser's window cut in half.
                // Only the newest one is kept (it is the latest run, dated by the file).
                if position > 0, !isEvent(source.log), !run.header.contains("|") { continue }
                let entry = indexByHeader.first { RunMatcher.matches(run, header: $0.runHeader ?? "") }
                if let entry { usedIndex.insert(entry.id) }
                // blocks with this exact banner that are older than this one
                let ordinal = source.runs[(position + 1)...].filter { $0.header == run.header }.count
                let title = kind(for: source.log).map(titleForKind) ?? titleForLog(source.log)
                rows.append(loggedRow(run, in: source.log, ordinal: ordinal, isNewest: position == 0,
                                      entry: entry, title: title, now: now, slots: slots,
                                      agentArguments: agentArguments, modified: modified))
            }
        }

        // 4. index-only entries
        for entry in index where !liveIDs.contains(entry.id) && !usedIndex.contains(entry.id) {
            rows.append(indexedRow(entry, title: titleForKind(entry.kind)))
        }

        // 5. tasks that leave no log and have not run
        let seen = Set(rows.compactMap(\.kind))
        for kind in [JobKind.memoryReport, .storageReport, .networkSnapshot]
        where !seen.contains(kind) && !hasOutput(kind) {
            rows.append(ActivityRow(
                id: "never:\(kind.rawValue)", source: .neverRan(kind), jobID: nil, title: titleForKind(kind),
                kind: kind, log: nil, intent: nil, flavor: nil, started: nil, finished: nil,
                trigger: .unknown, status: .none, result: "Hasn't run yet", reviewResult: nil, header: nil,
                needsReview: false, findings: 0, freedBytes: 0, memoryBytes: 0, closed: 0))
        }

        markNeedsReview(&rows, now: now, dismissed: dismissed)
        return rows
    }

    // MARK: - reading the logs

    /// The engine logs the join reads, each newest first. A crisis report is a
    /// file of its own, so the forensics log is its newest few reports.
    public static func readLogs() -> [LogRuns] {
        EngineLog.allCases.map { LogRuns(log: $0, runs: readRuns(for: $0)) }
    }

    public static func readRuns(for log: EngineLog) -> [LogRun] {
        guard log == .forensics else { return LogParser.runs(for: log, includingRestores: true) }
        return AnalyzersPaths.allForensics().prefix(10).enumerated().compactMap { position, url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = LogLines.lines(in: text)
            // the report names its own moment; that stamp, not the file's mtime, keeps the id fixed
            let stamp = lines.first.flatMap(headerDate).map { stampFormat.string(from: $0) }
                ?? url.deletingPathExtension().lastPathComponent
            return LogRun(id: position, header: "Memory crisis report \(stamp)", lines: Array(lines.prefix(200)))
        }
    }

    private static let stampFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - rows

    private static func loggedRow(_ run: LogRun, in log: EngineLog, ordinal: Int, isNewest: Bool,
                                  entry: JobLedgerEntry?, title: String, now: Date, slots: Slots,
                                  agentArguments: AgentArguments, modified: (EngineLog) -> Date?) -> ActivityRow {
        let summary = ActivitySummary.of(run, in: log)
        // an event log's day group is dated by its newest line, a block by its banner
        let date = headerDate(run.lines.first.map { eventLog(log) ? $0 : "" } ?? "")
            ?? headerDate(run.header)
            // a block whose banner fell out of the parser's window has no date of its own
            ?? (isNewest ? modified(log) : nil)
        let status: ActivityRow.Status
        var result = summary.text
        var review = summary.reviewText
        var findings = summary.findings
        if let entry, entry.cancelled {
            status = .stopped
            result = "Stopped"
            review = nil
            findings = 0
        } else if let entry, let code = entry.exit, code != 0 {
            status = .failed
            result = entry.kind.failureMessage(exitCode: code, intent: entry.intent, options: JobOptions())
            review = nil
            findings = 0
        } else {
            status = .done
        }
        let restore = RestoreBlock.isRestore(header: run.header)
        // a restore is always a person's click in the app; it has no task kind of its own
        let who: ActivityRow.Trigger = restore ? .you : entry.map { trigger(of: $0.trigger) }
            ?? attribute(log: log, header: run.header, date: date, slots: slots, agentArguments: agentArguments)
        let intent = entry?.intent ?? intent(of: run.header)
        return ActivityRow(
            id: "log:\(log.rawValue):\(run.header)#\(ordinal)",
            source: .logged(log, header: run.header, ordinal: ordinal), jobID: entry?.id,
            title: restore ? Names.Screen.undo : title,
            kind: restore ? nil : entry?.kind ?? kind(for: log), log: log, intent: intent,
            flavor: flavor(header: run.header, options: JobOptions(), kind: restore ? nil : entry?.kind ?? kind(for: log)),
            started: entry?.start ?? date, finished: entry?.end, trigger: who, status: status,
            result: result, reviewResult: review, header: run.header, needsReview: false,
            findings: findings, freedBytes: status == .done ? summary.freedBytes : 0,
            memoryBytes: status == .done ? summary.memoryBytes : 0, closed: status == .done ? summary.closed : 0)
    }

    private static func indexedRow(_ entry: JobLedgerEntry, title: String) -> ActivityRow {
        let status: ActivityRow.Status
        let result: String
        if entry.cancelled {
            status = .stopped
            result = "Stopped"
        } else if let code = entry.exit, code != 0 {
            status = .failed
            result = entry.kind.failureMessage(exitCode: code, intent: entry.intent, options: JobOptions())
        } else {
            status = .done
            result = ActivitySummary.of(.none, kind: entry.kind).text
        }
        return ActivityRow(
            id: "index:\(entry.id.uuidString)", source: .indexed(entry.id), jobID: entry.id, title: title,
            kind: entry.kind, log: entry.kind.log, intent: entry.intent,
            flavor: flavor(header: entry.runHeader, options: JobOptions(), kind: entry.kind),
            started: entry.start, finished: entry.end, trigger: trigger(of: entry.trigger), status: status,
            result: result, reviewResult: nil, header: entry.runHeader, needsReview: false, findings: 0,
            freedBytes: 0, memoryBytes: 0, closed: 0)
    }

    private static func placeholder(for log: EngineLog, title: String) -> ActivityRow {
        ActivityRow(id: "empty:\(log.rawValue)", source: .emptyLog(log), jobID: nil, title: title,
                    kind: kind(for: log), log: log, intent: nil, flavor: nil, started: nil, finished: nil,
                    trigger: owner(of: log) ?? .unknown, status: .none, result: "Hasn't run yet",
                    reviewResult: nil, header: nil, needsReview: false, findings: 0, freedBytes: 0,
                    memoryBytes: 0, closed: 0)
    }

    // MARK: - needs review

    /// "Waiting for your review" means what the app can actually do: a preview
    /// the store holds, finished within `JobStore.reviewWindow`, not dismissed,
    /// that found something, and that no newer run of the same task has replaced.
    /// An older preview, or one found in a log, is still listed with what it
    /// found, as found-but-not-applied: the app cannot apply it, and the way
    /// forward is a new preview.
    private static func markNeedsReview(_ rows: inout [ActivityRow], now: Date, dismissed: Set<UUID>) {
        var newest: [String: Int] = [:]
        // a restore is not a run of the task: it must not replace the waiting preview before it
        for (position, row) in rows.enumerated() where row.status == .done && row.intent != .run && !row.isRestore {
            guard let when = row.finished ?? row.started else { continue }
            if let current = newest[row.taskKey],
               let existing = rows[current].finished ?? rows[current].started, existing >= when { continue }
            newest[row.taskKey] = position
        }
        for position in newest.values {
            let row = rows[position]
            guard row.intent == .preview, row.findings > 0, case .live(let id) = row.source,
                  !dismissed.contains(id), let end = row.finished,
                  now.timeIntervalSince(end) <= JobStore.reviewWindow else { continue }
            rows[position].needsReview = true
        }
    }

    // MARK: - who started an untracked run

    /// What a run's own banner says about how it was started.
    enum Input: Equatable {
        case flags([String])
        case interactive
        case unsaid
    }

    static func input(in header: String) -> Input {
        if header.contains("input: interactive menu") { return .interactive }
        guard let range = header.range(of: "input: flags:") else { return .unsaid }
        let text = header[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("(none") { return .flags([]) }
        return .flags(text.split(separator: " ").map(String.init))
    }

    /// Reads the evidence a run carries, in this order, and asserts nothing else:
    ///  - the guard, the watcher and the crisis reports write their own logs;
    ///  - an interactive menu choice was made at a keyboard: Terminal;
    ///  - the guard's own flags: Guard;
    ///  - an approval list: the app's reviewed apply, so You (older runs, from before the index);
    ///  - the flags of an installed agent: Schedule, when they are distinctive,
    ///    or when they are just `--apply` and the run is within ten minutes of
    ///    the agent's slot;
    ///  - with no flags recorded at all, falling in an agent's slot is enough;
    ///  - anything else: Unknown.
    static func attribute(log: EngineLog, header: String, date: Date?, slots: Slots,
                          agentArguments: AgentArguments) -> ActivityRow.Trigger {
        if let owner = owner(of: log) { return owner }
        let nearSlot: Bool = date.map { date in
            slots(log, date).contains { abs($0.timeIntervalSince(date)) <= scheduleWindow }
        } ?? false
        switch input(in: header) {
        case .interactive:
            return .terminal
        case .flags(let flags):
            if flags == guardFlags, log == .memoryClean { return .guardian }
            if flags.contains("--only-pids") || flags.contains("--only-paths") { return .you }
            if let agent = agentArguments(log).first(where: { $0 == flags }) {
                let distinctive = agent.contains { $0 != "--apply" }
                return distinctive || nearSlot ? .schedule : .unknown
            }
            return .unknown
        case .unsaid:
            return nearSlot ? .schedule : .unknown
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

    static func eventLog(_ log: EngineLog) -> Bool {
        log == .guardLog || log == .persistence
    }

    /// Logs whose entries are events or whole files rather than banner-headed runs.
    private static func isEvent(_ log: EngineLog) -> Bool {
        log == .guardLog || log == .persistence || log == .forensics
    }

    /// Logs one background program owns outright.
    private static func owner(of log: EngineLog) -> ActivityRow.Trigger? {
        switch log {
        case .guardLog, .forensics, .persistence: .guardian
        default: nil
        }
    }

    /// The task a log's blocks belong to, for the human name and the icon.
    static func kind(for log: EngineLog) -> JobKind? {
        switch log {
        case .memoryClean: .memoryClean
        case .reclaim: .reclaim
        case .storageClean: .storageClean
        case .janitor: .janitor
        case .tempSpace: .tempClean
        case .spotlightAudit: .spotlight
        case .loginItems: .loginItems
        case .guardLog, .persistence, .forensics: nil
        }
    }

    /// "Daily" or "Deep" for the storage cleaner, from its banner (`mode=deep`)
    /// or, for a job just started, from its options.
    static func flavor(header: String?, options: JobOptions, kind: JobKind?) -> String? {
        guard kind == .storageClean else { return nil }
        if let header {
            if header.contains("mode=deep") { return "Deep" }
            if header.contains("mode=daily") { return "Daily" }
        }
        if options.deep { return "Deep" }
        if let replay = options.scheduleArguments, let at = replay.firstIndex(of: "--mode"),
           replay.indices.contains(at + 1) { return replay[at + 1].capitalized }
        return nil
    }

    /// A banner without "DRY RUN" is an action.
    private static func intent(of header: String) -> JobIntent? {
        let text = header.uppercased()
        if text.contains("DRY RUN") || text.contains("DRY-RUN") { return .preview }
        if text.contains("APPLY") { return .apply }
        return nil
    }

    /// The first `YYYY-MM-DD HH:MM[:SS]` in a banner, in the local zone; a
    /// bare date (an event log's day group) only when no time is there.
    static func headerDate(_ header: String) -> Date? {
        if let match = header.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/) {
            return date(Int(match.1), Int(match.2), Int(match.3), Int(match.4), Int(match.5),
                        match.6.flatMap { Int($0) } ?? 0)
        }
        if let match = header.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            return date(Int(match.1), Int(match.2), Int(match.3), 0, 0, 0)
        }
        return nil
    }

    private static func date(_ year: Int?, _ month: Int?, _ day: Int?, _ hour: Int?, _ minute: Int?,
                             _ second: Int?) -> Date? {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = second
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

    /// Each installed agent's arguments after the script path.
    @Sendable public static func installedArguments(for log: EngineLog) -> [[String]] {
        agentLabels(for: log).compactMap { ScheduleKit.programArguments(for: $0) }
    }

    /// Whether a task that writes no run log has left anything behind.
    public static func hasOutput(_ kind: JobKind) -> Bool {
        let fm = FileManager.default
        switch kind {
        case .memoryReport: return fm.fileExists(atPath: AnalyzersPaths.memoryLatestReport.path)
        case .storageReport: return fm.fileExists(atPath: AnalyzersPaths.storageLatestReport.path)
        case .networkSnapshot: return fm.fileExists(atPath: AnalyzersPaths.networkLog.path)
        default: return true
        }
    }
}
