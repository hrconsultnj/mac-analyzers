import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-trend-buckets` judges how a period's events become the bars of a Trends chart, on a guard log
// it writes itself at a fixed moment (nothing of the person's is read): the last 24 hours is 24 hourly buckets, every
// longer period is one bucket per calendar day, "Last N Days" being N buckets with today the last, every event inside a period is in
// exactly one bucket of it (the hour or day it happened in), nothing outside is, and what the guard and the cleaners
// freed or removed lands in the same buckets. Exits non-zero when a rule breaks.

func probeTrendBuckets() -> Never {
    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "ok  " : "FAIL") \(name): \(detail)")
        if !ok { failed = true }
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    // Friday 13 November 2026, 15:30 in New York: no daylight-saving change inside any period measured from it back to 3 days
    guard let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 15, minute: 30)) else { exit(2) }

    // one alert at each of these ages, in hours, and one kill 5 hours old that held 500 MB
    let ages: [Double] = [0.2, 2.5, 5, 20, 23.9, 25, 50, 71, 80, 150, 170, 300, 700, 800, 2_000, 2_300]
    let kill = 5.0
    var lines = ages.enumerated().map { index, hours in
        "\(formatter.string(from: now.addingTimeInterval(-hours * 3_600))) SPIKE pid=\(100 + index) +800MB now 1900MB  node /Users/x/p\(index)/node_modules/.bin/vite"
    }
    lines.append("\(formatter.string(from: now.addingTimeInterval(-kill * 3_600))) KILLED [hard-cap 6144MB] pid=900 rss=500MB  node /Users/x/web/node_modules/.bin/next dev")
    let log = ProbeScratch.folder("ma-probe-trend-buckets").appending(path: "guard.log")
    try? (lines.sorted().joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)

    let reapAt = now.addingTimeInterval(-3 * 3_600)
    let removedAt = now.addingTimeInterval(-30 * 3_600)

    for period in ReportPeriod.allCases {
        let events = GuardLogParser.allEvents(fromLog: log, since: period.start(now: now, calendar: calendar))
        let buckets = TrendBuckets.make(period: period, now: now, calendar: calendar, events: events,
                                        freed: [(reapAt, 200)], removed: [(removedAt, 4_000)])
        let starts = buckets.map(\.start)
        let unit = period.bucket == .hour ? "hourly" : "daily"

        // the number of bars
        // 24 hours is 24 bars; "Last N Days" is N bars, today included
        let wantedCount = period == .day ? 24 : period.rawValue / 24
        check("\(period.title) is \(wantedCount) \(unit) buckets", buckets.count == wantedCount,
              "\(buckets.count) buckets, \(period.bucket == .hour ? "the current clock hour and the 23 before it" : "today and the \(wantedCount - 1) days before it")")
        // the period begins exactly where its first bar does, so no bar covers more than its own hour or day
        check("\(period.title) begins where its first bar does", starts.first == (period.bucket == .hour
              ? period.start(now: now, calendar: calendar) : calendar.startOfDay(for: period.start(now: now, calendar: calendar))),
              starts.first.map { formatter.string(from: $0) } ?? "no bars")

        // contiguous, oldest first, each one hour or one calendar day after the one before, the last holding now
        let step = period.bucket.component
        let contiguous = zip(starts, starts.dropFirst()).allSatisfy { calendar.date(byAdding: step, value: 1, to: $0) == $1 }
        let lastHoldsNow = starts.last.map { $0 <= now && calendar.date(byAdding: step, value: 1, to: $0).map { now < $0 } == true } == true
        check("\(period.title): buckets run oldest first without a gap and the last holds now", contiguous && lastHoldsNow, "\(starts.count) starts")

        // every event of the period is in one bucket, none are lost or counted twice
        let counted = buckets.reduce(0) { $0 + $1.events }
        check("\(period.title): every event inside it is in exactly one bucket", counted == events.count && !events.isEmpty,
              "\(counted) in the buckets, \(events.count) read")

        // each event is in the bucket of the hour or day it happened in (the first bucket also takes the part of its hour
        // that the rolling 24 hours reaches back into)
        let misplaced = events.filter { event in
            guard let found = buckets.first(where: { $0.events > 0 && $0.start == calendar.dateInterval(of: step, for: event.date)?.start })
                    ?? buckets.first else { return true }
            return found.start != calendar.dateInterval(of: step, for: event.date)?.start && found.start != starts.first
        }
        check("\(period.title): each event is in the bucket of the \(period.bucket == .hour ? "hour" : "day") it happened in", misplaced.isEmpty,
              "\(misplaced.count) misplaced")

        // what was freed and removed lands where it happened
        let freedTotal = buckets.reduce(0) { $0 + $1.freedMB }
        let inside = Int(period.rawValue) >= 24
        check("\(period.title): the 500 MB the guard freed and the 200 MB a cleanup closed are in the buckets", inside && freedTotal == 700,
              "\(freedTotal) MB")
        let removedTotal = buckets.reduce(Int64(0)) { $0 + $1.removedBytes }
        // 30 hours ago is inside every period but the last 24 hours, which must not take it into its first hour
        let removedWanted: Int64 = period == .day ? 0 : 4_000
        check("\(period.title): the 4,000 bytes removed 30 hours ago are \(period == .day ? "not in it" : "in it")",
              removedTotal == removedWanted, "\(removedTotal) bytes")
    }

    // an event 2.5 hours old sits in the hourly bucket that starts at the top of that hour
    let hourly = TrendBuckets.make(period: .day, now: now, calendar: calendar,
                                   events: GuardLogParser.allEvents(fromLog: log, since: ReportPeriod.day.start(now: now, calendar: calendar)))
    let target = calendar.dateInterval(of: .hour, for: now.addingTimeInterval(-2.5 * 3_600))?.start
    let holder = hourly.first { $0.start == target }
    check("a spike 2.5 hours ago is in the bucket that starts at \(target.map { formatter.string(from: $0) } ?? "?")", holder?.spikes == 1,
          "\(holder?.spikes ?? -1) spikes there")

    // a log written longer ago than the period is not read for it: the 24 hours reads fewer bytes than the 90 days
    let short = GuardLogReader.read(log, since: ReportPeriod.day.start(now: now, calendar: calendar))
    check("the last 24 hours stops reading at its own start", short.reachedCutoff && short.lines.count < lines.count,
          "\(short.lines.count) of \(lines.count) lines read")
    ProbeScratch.finish(failed ? 1 : 0)
}
