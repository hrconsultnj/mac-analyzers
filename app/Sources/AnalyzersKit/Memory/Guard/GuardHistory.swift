import Foundation
import Synchronization

/// What a person is shown for Memory Guard: the guard's log read as a history
/// — typed entries, repeats folded into one row, rows grouped by day with a
/// total per day. Plain data, so `agent-runner --probe-guard-history` prints
/// exactly what the screen shows.
///
/// How it is put together, one job per file:
///   GuardEntry.swift             one event in words (title, outcome, why)
///   GuardHistory.swift           this file: scopes, rows, days, building
///   GuardHistory+Entries.swift   log events to entries (names, projects, reasons)
///   CrisisReportSummary.swift    a crisis report as apps, not 25 processes
public struct GuardHistory: Sendable {

    public enum Scope: String, CaseIterable, Identifiable, Sendable {
        /// The raw values are keys (a deep link, the remembered tab); the names are `Names`.
        case all, stopped, alerts, crisisReports

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: Names.Scope.all
            case .stopped: Names.Guard.stopped
            case .alerts: Names.Guard.alerts
            case .crisisReports: Names.crisisReports
            }
        }

        public var symbol: String {
            switch self {
            case .all: "list.bullet"
            case .stopped: "stop.circle"
            case .alerts: "exclamationmark.triangle"
            case .crisisReports: "stethoscope"
            }
        }

        func includes(_ kind: GuardEntry.Kind) -> Bool {
            switch self {
            case .all: true
            case .stopped: kind == .stopped
            case .alerts: kind == .spike || kind == .overLimit || kind == .pressure || kind == .cpu
            case .crisisReports: kind == .crisisReport
            }
        }
    }

    /// One line in the list. A repeat — nine CPU alerts for the same program
    /// in a day — is one row that knows its entries.
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: String
        public let kind: GuardEntry.Kind
        public let title: String
        public let outcome: String
        /// The first and last entry's time (equal for a single event).
        public let start: Date
        public let end: Date
        /// Oldest first.
        public let entries: [GuardEntry]

        public var count: Int { entries.count }
        public var isGroup: Bool { entries.count > 1 }
        /// The entry a single row stands for; the newest of a group.
        public var lead: GuardEntry { entries.last ?? entries[0] }
        /// "9:41 PM", or "2:48 AM – 5:24 PM" for a repeat that spans time.
        public var timeText: String {
            let style = Date.FormatStyle(locale: Locale(identifier: "en_US")).hour().minute()
            let first = start.formatted(style)
            let last = end.formatted(style)
            return first == last ? first : "\(first) – \(last)"
        }

        /// Every log line behind the row, oldest first, for the raw-output screen.
        public var rawText: String { entries.map(\.raw).joined(separator: "\n") }
    }

    public struct Day: Identifiable, Sendable {
        public let day: Date
        /// Newest first.
        public let rows: [Row]
        public var id: String { String(Int(day.timeIntervalSince1970)) }

        /// Stops that happened. One that found the process already gone is not one of them.
        public var stopped: Int { rows.reduce(0) { $0 + $1.entries.filter { $0.kind == .stopped && !$0.stopFailed }.count } }
        /// Tries that found the process already ended.
        public var alreadyGone: Int { rows.reduce(0) { $0 + $1.entries.filter(\.stopFailed).count } }
        public var alerts: Int { count(of: [.spike, .overLimit, .pressure, .cpu]) }
        public var reports: Int { count(of: [.crisisReport]) }

        private func count(of kinds: Set<GuardEntry.Kind>) -> Int {
            rows.reduce(0) { $0 + (kinds.contains($1.kind) ? $1.count : 0) }
        }

        /// "2 stopped · 14 alerts · 1 crisis report".
        public var summary: String {
            var parts: [String] = []
            if stopped > 0 { parts.append("\(stopped) stopped") }
            if alerts > 0 { parts.append("\(alerts) \(alerts == 1 ? "alert" : "alerts")") }
            if reports > 0 { parts.append("\(reports) crisis \(reports == 1 ? "report" : "reports")") }
            if alreadyGone > 0 { parts.append("\(alreadyGone) already gone") }
            return parts.joined(separator: " · ")
        }

        public func title(now: Date, calendar: Calendar = .current) -> String {
            ActivityDay(day: day, rows: []).title(now: now, calendar: calendar)
        }
    }

    /// The most rows one update of the list may add: a SwiftUI `List` that gains
    /// roughly 225 rows in one update logs an AppKit warning, so the list is
    /// shown a page at a time.
    public static let pageRows = 200

    /// Where the next page of `days` ends (exclusive), starting at `start`: whole
    /// days only, stopping before the page would pass `budget` rows, and always
    /// at least one day (a day is never split, so a day with more rows than the
    /// budget is a page of its own).
    public static func pageEnd(of days: [Day], from start: Int, budget: Int = pageRows) -> Int {
        guard start < days.count else { return days.count }
        var end = start
        var rows = 0
        while end < days.count {
            let next = days[end].rows.count
            if end > start, rows + next > budget { break }
            rows += next
            end += 1
        }
        return end
    }

    /// The window the log is read for.
    public static let windowDays = 90

    /// How far back the history really goes. The log is read back to the
    /// window's start, so this is normally the window; it is shorter when the
    /// log is younger than the window or the read hit its size bound — and
    /// then the screen says so instead of naming a window it does not cover.
    public struct Coverage: Sendable {
        public let oldest: Date?
        public let reachedWindow: Bool
        public let bytesRead: Int
        public let eventCount: Int
    }

    public let entries: [GuardEntry]
    public let coverage: Coverage

    public var rows: [Row] { GuardHistory.rows(from: entries) }

    public static let empty = GuardHistory(entries: [],
                                           coverage: Coverage(oldest: nil, reachedWindow: true, bytesRead: 0, eventCount: 0))

    /// How many entries a scope holds, for its tab. A stop that found the process already gone
    /// is not counted as a stop.
    public func count(_ scope: Scope) -> Int {
        entries.filter { scope.includes($0.kind) && !($0.kind == .stopped && $0.stopFailed && scope == .stopped) }.count
    }

    /// Stops that happened (the subtitle), not tries that found the process gone.
    public var stoppedCount: Int { entries.filter { $0.kind == .stopped && !$0.stopFailed }.count }

    /// One row of the history by its id, wherever it is.
    ///
    /// A row's id starts with its kind and a time, so only that one day's entries are grouped, not the whole history.
    /// What follows the time is what the row IS, not where a read happened to start:
    ///   - a stop or a crisis report: its own entry (one log line);
    ///   - a group of alerts about one program: the day and the program, so the same group has the same id in a read that
    ///     begins later (a list whose cache ran out, an hour that turned) and loses the group's earliest alerts;
    ///   - an episode of pressure: the time of its first reading. A read that begins inside the episode drops that reading,
    ///     so the episode is then found as the pressure row that begins at the read's own start (`coverage.oldest`), within an
    ///     hour of the time the id names.
    public func row(id: String, calendar: Calendar = .current) -> Row? {
        let parts = id.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let epoch = TimeInterval(parts[1]) else { return nil }
        let moment = Date(timeIntervalSince1970: epoch)
        let day = calendar.startOfDay(for: moment)
        let sameDay = entries.filter { calendar.startOfDay(for: $0.date) == day }
        let rows = GuardHistory.rows(from: sameDay, calendar: calendar)
        if let exact = rows.first(where: { $0.id == id }) { return exact }
        guard parts[0] == GuardEntry.Kind.pressure.rawValue, let oldest = coverage.oldest else { return nil }
        return rows.first { $0.kind == .pressure && $0.start == oldest && $0.start > moment && $0.start.timeIntervalSince(moment) <= 3_600 }
    }

    // MARK: - reading

    /// A log to read instead of the real one, so every state of the screen (a
    /// stop, a crisis report, an empty history) can be rendered headless without
    /// touching the real log. Test-support only: SnapshotRunner sets it from its
    /// `--guard-log` option; the app and the environment cannot.
    @_spi(TestSupport)
    public static func useLog(at url: URL?) { logOverride.withLock { $0 = url } }
    private static let logOverride = Mutex<URL?>(nil)

    /// The guard's own log, back to the start of the first day in the window.
    ///
    /// Blocking (it reads the log and names every program once): call it off
    /// the main actor and not on every refresh — `GuardHistoryModel` does both.
    public static func load(days: Int = windowDays, now: Date = Date()) -> GuardHistory {
        load(since: periodStart(hours: days * 24, now: now))
    }

    /// Where a period of `hours` begins, the one rule every screen, total, chart and the menu-bar panel's "Recent Events"
    /// share. The last 24 hours begins ON the hour: the current clock hour and the 23 before it, so a chart of it is 24
    /// equal bars (the current one only up to now). "Last N days" is N days counting today: it begins at the start of the
    /// day N-1 days back, so 7 days is today and the 6 days before it, 7 bars, and the oldest day is whole.
    public static func periodStart(hours: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if hours <= 24 {
            let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            return calendar.date(byAdding: .hour, value: -(max(hours, 1) - 1), to: thisHour) ?? thisHour
        }
        return calendar.date(byAdding: .day, value: -(hours / 24 - 1), to: calendar.startOfDay(for: now)) ?? now
    }

    /// Everything from `start` on. The log is read backwards only as far as `start`, so a short period costs a short read
    /// however long the log is.
    public static func load(since start: Date) -> GuardHistory {
        guard let url = logOverride.withLock({ $0 }) ?? EngineLog.guardLog.url else { return .empty }
        let reading = GuardLogReader.read(url, since: start)
        let events = reading.lines.compactMap { GuardLogParser.parseLine($0) }
        let oldest = events.map(\.date).min()
        return GuardHistory(entries: entries(from: events),
                            coverage: Coverage(oldest: oldest, reachedWindow: reading.reachedCutoff,
                                               bytesRead: reading.bytesRead, eventCount: events.count))
    }

    public static func build(events: [GuardEvent]) -> GuardHistory {
        GuardHistory(entries: entries(from: events),
                     coverage: Coverage(oldest: events.map(\.date).min(), reachedWindow: true,
                                        bytesRead: 0, eventCount: events.count))
    }

    // MARK: - what a screen asks

    /// Rows in a scope that match a search, grouped by day, newest first.
    public func days(scope: Scope = .all, search: String = "",
                     calendar: Calendar = .current) -> [Day] {
        let wanted = search.trimmingCharacters(in: .whitespaces).lowercased()
        let kept = entries.filter { entry in
            scope.includes(entry.kind) && (wanted.isEmpty || GuardHistory.matches(entry, wanted))
        }
        var byDay: [Date: [GuardEntry]] = [:]
        for entry in kept { byDay[calendar.startOfDay(for: entry.date), default: []].append(entry) }
        return byDay
            .map { day, entries in Day(day: day, rows: GuardHistory.rows(from: entries)) }
            .sorted { $0.day > $1.day }
    }

    private static func matches(_ entry: GuardEntry, _ wanted: String) -> Bool {
        let haystack = [entry.title, entry.outcome, entry.subject, entry.project ?? "",
                        entry.pid.map { "pid \($0) \($0)" } ?? ""]
        return haystack.contains { $0.lowercased().contains(wanted) }
    }

    /// Entries folded into rows, newest first. Alerts about the same program
    /// on one day are one row; so are consecutive pressure readings (one
    /// episode of low memory). A stop or a crisis report is always its own row.
    static func rows(from entries: [GuardEntry], calendar: Calendar = .current) -> [Row] {
        let oldestFirst = entries.sorted { $0.date < $1.date }
        var rows: [Row] = []

        // repeats: same kind, subject and project, on one day
        var repeats: [String: [GuardEntry]] = [:]
        var order: [String] = []
        func remember(_ key: String, _ entry: GuardEntry) {
            if repeats[key] == nil { order.append(key) }
            repeats[key, default: []].append(entry)
        }

        // episodes of pressure: readings no more than ten minutes apart
        var episode: [GuardEntry] = []
        func closeEpisode() {
            guard !episode.isEmpty else { return }
            rows.append(row(for: episode, calendar: calendar))
            episode = []
        }

        for entry in oldestFirst {
            switch entry.kind {
            case .stopped, .crisisReport:
                rows.append(row(for: [entry], calendar: calendar))
            case .pressure:
                if let last = episode.last,
                   entry.date.timeIntervalSince(last.date) > 600
                    || (entry.pressureLevel ?? 0) != (last.pressureLevel ?? 0) {
                    closeEpisode()
                }
                episode.append(entry)
            case .spike, .overLimit, .cpu:
                let day = calendar.startOfDay(for: entry.date).timeIntervalSince1970
                remember("\(entry.kind.rawValue)|\(entry.subject)|\(entry.project ?? "")|\(Int(day))", entry)
            }
        }
        closeEpisode()
        for key in order { rows.append(row(for: repeats[key] ?? [], calendar: calendar)) }
        return rows.sorted { ($0.end, $0.id) > ($1.end, $1.id) }
    }

    private static func row(for entries: [GuardEntry], calendar: Calendar) -> Row {
        let first = entries[0]
        let last = entries[entries.count - 1]
        let id: String
        switch first.kind {
        case .spike, .overLimit, .cpu:
            // the day and the program: the same group in every read of that day, whatever its earliest alerts
            let day = Int(calendar.startOfDay(for: first.date).timeIntervalSince1970)
            id = "\(first.kind.rawValue)-\(day)-\(stableKey("\(first.subject)|\(first.project ?? "")"))"
        default:
            id = "\(first.kind.rawValue)-\(Int(first.date.timeIntervalSince1970))-\(first.id)"
        }
        guard entries.count > 1 else {
            return Row(id: id, kind: first.kind, title: first.title, outcome: first.outcome,
                       start: first.date, end: first.date, entries: entries)
        }
        let span = last.date.timeIntervalSince(first.date)
        switch first.kind {
        case .pressure:
            let level = (first.pressureLevel ?? 0) >= 4 ? "critical" : "high"
            return Row(id: id, kind: .pressure,
                       title: "Memory pressure was \(level) for \(minutes(span))",
                       outcome: first.outcome, start: first.date, end: last.date, entries: entries)
        case .cpu:
            return Row(id: id, kind: .cpu,
                       title: "\(entries.count) CPU alerts for \(first.subjectWithProject)",
                       outcome: "Only alerts — nothing was stopped.",
                       start: first.date, end: last.date, entries: entries)
        case .spike, .overLimit:
            let biggest = entries.compactMap(\.memoryMB).max()
            let size = biggest.map { " Biggest: \(GuardEntry.gigabytes($0))." } ?? ""
            return Row(id: id, kind: first.kind,
                       title: "\(entries.count) memory alerts for \(first.subjectWithProject)",
                       outcome: "Only alerts — nothing was stopped.\(size)",
                       start: first.date, end: last.date, entries: entries)
        case .stopped, .crisisReport:
            return Row(id: id, kind: first.kind, title: first.title, outcome: first.outcome,
                       start: first.date, end: last.date, entries: entries)
        }
    }

    /// A short key that is the same in every run (FNV-1a), unlike `String.hashValue`, which changes each launch.
    private static func stableKey(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    /// "4 minutes", "1 hour 5 minutes", or "under a minute".
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        if total < 1 { return "under a minute" }
        if total < 60 { return total == 1 ? "1 minute" : "\(total) minutes" }
        let hours = total / 60, rest = total % 60
        let h = hours == 1 ? "1 hour" : "\(hours) hours"
        return rest == 0 ? h : "\(h) \(rest) \(rest == 1 ? "minute" : "minutes")"
    }
}
