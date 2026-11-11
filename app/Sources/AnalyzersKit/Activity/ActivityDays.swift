import Foundation

/// Activity's sections: "Running now", one per day, then what has never run.
/// Pure, so the probe prints exactly what the screen groups.
public struct ActivitySections: Sendable {
    public let running: [ActivityRow]
    public let days: [ActivityDay]
    public let neverRan: [ActivityRow]

    public init(running: [ActivityRow], days: [ActivityDay], neverRan: [ActivityRow]) {
        self.running = running
        self.days = days
        self.neverRan = neverRan
    }
}

/// One day of history: its rows, newest first, and what that day added up to.
public struct ActivityDay: Identifiable, Sendable {
    /// Midnight of the day; nil collects rows with no date at all.
    public let day: Date?
    public let rows: [ActivityRow]

    public init(day: Date?, rows: [ActivityRow]) {
        self.day = day
        self.rows = rows
    }

    public var id: String { day.map { String(Int($0.timeIntervalSince1970)) } ?? "undated" }

    /// Runs a person or a schedule started; events (guard days, crisis
    /// reports, startup changes) are not runs.
    public var runs: Int { rows.filter { !$0.isEventLog && $0.status != .none }.count }
    public var failed: Int { rows.filter(\.isFailed).count }
    public var toReview: Int { rows.filter(\.needsReview).count }
    /// Disk space only. Memory is another thing: it is counted apart.
    public var freedBytes: Int64 { rows.map(\.freedBytes).reduce(0, +) }
    public var memoryBytes: Int64 { rows.map(\.memoryBytes).reduce(0, +) }
    public var closedProcesses: Int { rows.map(\.closed).reduce(0, +) }
    public var events: Int { rows.filter(\.isEventLog).count }

    /// "Today", "Yesterday", "Monday, Nov 8", or with the year once it is another year.
    public func title(now: Date, calendar: Calendar = .current) -> String {
        guard let day else { return "Earlier" }
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let format = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar,
                                      timeZone: calendar.timeZone)
        return sameYear ? day.formatted(format.weekday(.wide).month(.abbreviated).day())
                        : day.formatted(format.weekday(.wide).month(.abbreviated).day().year())
    }

    /// "6 runs · freed 12.4 GB · closed 3 processes, 120 MB · 1 failed", or what is there when it holds only events.
    public var summary: String {
        var parts: [String] = []
        if runs > 0 { parts.append(ActivitySummary.plural(runs, "run", "runs")) }
        if freedBytes > 0 { parts.append("freed \(ByteSize.format(freedBytes))") }
        if closedProcesses > 0 {
            parts.append("closed \(ActivitySummary.plural(closedProcesses, "process", "processes")), \(ByteSize.format(memoryBytes))")
        }
        if failed > 0 { parts.append("\(failed) failed") }
        if toReview > 0 { parts.append("\(toReview) to review") }
        if parts.isEmpty { parts.append(ActivitySummary.plural(rows.count, "entry", "entries")) }
        return parts.joined(separator: " · ")
    }
}

public enum ActivityGrouping {

    public static func sections(_ rows: [ActivityRow], calendar: Calendar = .current) -> ActivitySections {
        // what is running first, then what waits, each in the order it was started
        let running = rows.filter(\.isRunning).sorted {
            if ($0.status == .running) != ($1.status == .running) { return $0.status == .running }
            return ($0.started ?? .distantFuture) < ($1.started ?? .distantFuture)
        }
        let never = rows.filter { $0.status == .none }.sorted { $0.title < $1.title }
        let history = rows.filter { !$0.isRunning && $0.status != .none }

        var byDay: [Date?: [ActivityRow]] = [:]
        for row in history {
            byDay[row.started.map { calendar.startOfDay(for: $0) }, default: []].append(row)
        }
        let days = byDay
            .map { day, rows in
                ActivityDay(day: day, rows: rows.sorted {
                    ($0.started ?? .distantPast, $1.id) > ($1.started ?? .distantPast, $0.id)
                })
            }
            .sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
        return ActivitySections(running: running, days: days, neverRan: never)
    }
}
