import Foundation

/// What a finished job found, read back from the engine's own log.
public struct JobOutcome: Sendable {
    public enum Parsed: Sendable {
        case reap(ReapRun)
        case storage(StorageCleanRun)
        case temp(TempCleanRun)
        case spotlight(SpotlightAuditRun)
        case loginItems(LoginItemsRun)
        /// The kind writes no run log the app parses (reports, snapshots, agents).
        case none
    }

    public let parsed: Parsed
    /// The log block that was parsed, if there was one.
    public let run: LogRun?
    public let match: RunMatcher.Match

    @_spi(TestSupport) public init(parsed: Parsed, run: LogRun?, match: RunMatcher.Match) {
        self.parsed = parsed
        self.run = run
        self.match = match
    }

    /// Set when the run shown is a guess, so a screen can say so.
    public var note: String? {
        switch match {
        case .exact, .noLog: nil
        case .newestFallback(let reason): reason
        }
    }
}

/// Finds the log block that belongs to one job.
///
/// The old way read "the newest run in the log", which is wrong whenever
/// something else (the schedule, Terminal, a second job) wrote a block in
/// between. Instead the job remembers the banner line its own stdout printed
/// (`<task> | DRY RUN | <date>`), and the outcome is parsed from the block
/// whose header is that banner. Only when nothing matches does it fall back to
/// the newest block, and it says so.
public enum RunMatcher {

    public enum Match: Sendable, Equatable {
        case exact
        case newestFallback(String)
        case noLog
    }

    // MARK: - the banner

    /// The run banner, if `line` is one: every engine banner has a `|`
    /// separator and either the mode (`DRY RUN`, `APPLY`) or a date. Group
    /// lines, rules and bracketed receipts are never banners.
    public static func banner(in line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.contains("|"),
              !text.hasPrefix("#"), !text.hasPrefix("="), !text.hasPrefix("["),
              text.contains("DRY RUN") || text.contains("APPLY") || text.contains(/\d{4}-\d{2}-\d{2}/)
        else { return nil }
        return text
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `LogParser` joins a banner of up to three lines with " · ", so the
    /// banner we captured is the whole header or its first line.
    static func matches(_ run: LogRun, header: String) -> Bool {
        let wanted = normalized(header)
        let have = normalized(run.header)
        return have == wanted || have.hasPrefix(wanted + " ·")
    }

    // MARK: - selecting

    /// The newest block that is this job's: its banner matches and does not
    /// show it began before the job did.
    public static func select(from runs: [LogRun], header: String?, startedAt: Date? = nil)
        -> (run: LogRun, match: Match)? {
        if let header, let hit = runs.first(where: { run in
            matches(run, header: header)
                && (startedAt.map { RunDate.isNotBefore(banner: run.header, start: $0) } ?? true)
        }) {
            return (hit, .exact)
        }
        guard let newest = runs.first else { return nil }
        return (newest, .newestFallback(header == nil ? Reason.noBanner : Reason.notFound))
    }

    /// Why a run's results are not shown. Full sentences: a screen says them as they are.
    public enum Reason {
        public static let noBanner = "This run printed no banner, so its own results can't be told from another run's."
        public static let notFound = "This run's own results couldn't be found in the log."
        public static let tooLarge = "This run's results are too large to review: they are more than 32 MB of log."
    }

    /// Reads the log and parses the matching run. Touches the disk — call it
    /// off the main actor.
    ///
    /// The common case reads the log's last 256 KB, as it always has. Only when
    /// the banner is not in that window (a very large run) does it read back
    /// further, to a fixed reach; a run beyond that stays a fallback, which
    /// refuses an apply.
    public static func outcome(kind: JobKind, header: String?, startedAt: Date? = nil) -> JobOutcome {
        outcome(kind: kind, in: kind.log?.url, header: header, startedAt: startedAt)
    }

    /// The same over any log file, so a probe can read a stand-in log the way the real one is read.
    public static func outcome(kind: JobKind, in logURL: URL?, header: String?, startedAt: Date? = nil) -> JobOutcome {
        guard let url = logURL else {
            return JobOutcome(parsed: .none, run: nil, match: .noLog)
        }
        var picked = select(from: LogParser.runs(at: url), header: header, startedAt: startedAt)
        // A block from the window that holds another run's banner is two runs the parser
        // could not tell apart (the janitor's log has no separator between runs): it is
        // not trusted, and the run is read again from its own banner.
        if let current = picked, current.match == .exact,
           current.run.lines.contains(where: { banner(in: $0) != nil }) {
            picked = (current.run, .newestFallback(Reason.notFound))
        }
        if picked?.match != .exact, let header {
            switch WholeRun.find(banner: header, in: url, notBefore: startedAt) {
            case .block(let block): picked = (block.run, .exact)
            case .tooLarge:
                if let current = picked { picked = (current.run, .newestFallback(Reason.tooLarge)) }
            case .notFound: break
            }
        }
        guard let picked else {
            return JobOutcome(parsed: .none, run: nil, match: .noLog)
        }
        let run = picked.run
        let parsed: JobOutcome.Parsed = switch kind {
        case .memoryClean, .reclaim:
            .reap(ReapParser.parse(runHeader: run.header, lines: run.lines))
        case .storageClean, .janitor:
            .storage(StorageCleanParser.parse(runHeader: run.header, lines: run.lines))
        case .tempClean:
            .temp(TempCleanParser.parse(runHeader: run.header, lines: run.lines))
        case .spotlight:
            .spotlight(SpotlightAuditParser.parse(runHeader: run.header, lines: run.lines))
        case .loginItems:
            .loginItems(LoginItemsParser.parse(runHeader: run.header, lines: run.lines))
        default:
            .none
        }
        return JobOutcome(parsed: parsed, run: run, match: picked.match)
    }
}
