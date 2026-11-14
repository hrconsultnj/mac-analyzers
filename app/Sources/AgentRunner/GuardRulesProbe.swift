import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-guard-rules` judges Memory Guard's history on a log it writes itself
// (a temporary folder; nothing of the person's is read): a stop that found its process already
// gone is not a stop, repeats and pressure readings fold into rows, a half-written last line is
// left out, a period starts at the start of its first day, and a list never gains more than a page
// of rows at once. Exits non-zero when a rule breaks.

func probeGuardRules() -> Never {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let today = calendar.startOfDay(for: Date())
    func stamp(daysAgo: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> String {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        let moment = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day) ?? day
        return formatter.string(from: moment)
    }

    var lines: [String] = []
    // two days ago: two stops, a stop that found its process already gone, three alerts about one
    // program (one row), five pressure readings ten minutes apart or less (one episode), a crisis report
    lines.append("\(stamp(daysAgo: 2, 9, 0)) KILLED [hard-cap 6144MB] pid=4001 rss=7000MB  node /Users/x/web/node_modules/.bin/next dev")
    lines.append("\(stamp(daysAgo: 2, 9, 5)) KILLED [hard-cap 6144MB] pid=4002 rss=6900MB  node /Users/x/api/node_modules/.bin/vite")
    lines.append("\(stamp(daysAgo: 2, 9, 6)) KILL-FAIL pid=4003 already gone")
    for minute in [20, 25, 30] {
        lines.append("\(stamp(daysAgo: 2, 10, minute)) SPIKE pid=4100 +900MB now 2100MB  node /Users/x/web/node_modules/.bin/next dev")
    }
    for minute in [0, 4, 9, 13, 18] { lines.append("\(stamp(daysAgo: 2, 11, minute)) PRESSURE warning (level 2)") }
    lines.append("\(stamp(daysAgo: 2, 12, 0)) FORENSICS written: /tmp/guard-critical-120000.log")
    // sixty older days with five different programs each: three hundred rows, for the paging rule
    let tools = ["vite", "next dev", "tsc --watch", "esbuild", "webpack serve"]
    for day in 3...62 {
        for (program, tool) in tools.enumerated() {
            lines.append("\(stamp(daysAgo: day, 8 + program, 0)) SPIKE pid=\(5000 + day * 10 + program) +800MB now 1900MB  node /Users/x/p/node_modules/.bin/\(tool)")
        }
    }
    // an alert at five past midnight on the first day of the seven-day period
    lines.append("\(stamp(daysAgo: 7, 0, 5)) SPIKE pid=6001 +700MB now 1700MB  node /Users/x/edge/node_modules/.bin/vite")
    let ordered = lines.sorted()
    // the guard is writing the last line as this reads: it has no newline yet
    let halfWritten = "\(stamp(daysAgo: 0, 0, 1)) KILLED [hard-cap 6144MB] pid=99999 rss=7000MB  node /Users/x/half"
    let url = ProbeScratch.folder("ma-probe-guard").appending(path: "guard.log")
    try? (ordered.joined(separator: "\n") + "\n" + halfWritten).write(to: url, atomically: true, encoding: .utf8)
    GuardHistory.useLog(at: url)

    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "ok  " : "FAIL") \(name): \(detail)")
        if !ok { failed = true }
    }

    let history = GuardHistory.load(days: 90)
    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
    let day = history.days().first { calendar.isDate($0.day, inSameDayAs: twoDaysAgo) }
    check("a stop is counted, a try that found the process gone is not", history.stoppedCount == 2 && day?.stopped == 2 && day?.alreadyGone == 1,
          "stopped \(history.stoppedCount), that day: \(day?.stopped ?? -1) stopped, \(day?.alreadyGone ?? -1) already gone")
    check("the day's summary says so", day?.summary.contains("1 already gone") == true, day?.summary ?? "no day")
    check("three alerts about one program are one row", day?.rows.filter { $0.kind == .spike }.map(\.count) == [3],
          "\(day?.rows.filter { $0.kind == .spike }.map(\.count) ?? [])")
    check("five pressure readings close together are one row", day?.rows.filter { $0.kind == .pressure }.map(\.count) == [5],
          "\(day?.rows.filter { $0.kind == .pressure }.map(\.count) ?? [])")
    check("a half-written last line is left out", !history.entries.contains { $0.pid == 99_999 }, "events read: \(history.coverage.eventCount)")

    // a period starts at the start of its first day
    let week = GuardHistory.load(days: 7)
    check("the first day of a period is whole (an alert at 00:05 is in)", week.entries.contains { $0.pid == 6001 },
          "events in the 7-day period: \(week.coverage.eventCount)")
    check("and nothing older is", !week.entries.contains { ($0.pid ?? 0) >= 5000 + 8 * 10 && ($0.pid ?? 0) < 6000 }, "rows from eight days ago and older are left out")

    // the list gains a page at a time, whole days, and never passes the rule unless one day is bigger
    let days = history.days()
    var start = 0, steps = 0, largest = 0, shown = 0
    while start < days.count {
        let end = GuardHistory.pageEnd(of: days, from: start)
        let rows = days[start..<end].reduce(0) { $0 + $1.rows.count }
        largest = max(largest, rows); shown += rows; steps += 1; start = end
    }
    let total = days.reduce(0) { $0 + $1.rows.count }
    check("a page is whole days and at most \(GuardHistory.pageRows) rows", largest <= GuardHistory.pageRows, "largest page \(largest) rows in \(steps) steps")
    check("the pages together show every row once", shown == total && steps > 1, "\(shown) of \(total) rows")
    check("days run newest first", zip(days, days.dropFirst()).allSatisfy { $0.day > $1.day }, "\(days.count) days")
    check("row ids are unique", Set(days.flatMap { $0.rows.map(\.id) }).count == total, "\(total) rows")

    // the periods the menu offers, on a log of its own: alerts 2 h, 30 h, 3.5 days, 6 days, 40 days and 100 days ago
    let now = Date()
    let ages = [2.0, 30, 84, 144, 960, 2_400]
    let periodLog = ProbeScratch.folder("ma-probe-guard-periods").appending(path: "guard.log")
    let periodLines = ages.enumerated().map { index, hours in
        "\(formatter.string(from: now.addingTimeInterval(-hours * 3_600))) SPIKE pid=\(7_000 + index) +800MB now 1900MB  node /Users/x/p\(index)/node_modules/.bin/vite"
    }
    // a long log, in time order like the real one: the 100- and 40-day-old alerts, then 8,000 from 20 days ago, then the rest;
    // a short period stops before the filler, a long one has to read through it
    let filler = (0..<8_000).map { index in
        "\(formatter.string(from: now.addingTimeInterval(-20 * 86_400 + Double(index)))) SPIKE pid=\(20_000 + index) +800MB now 1900MB  node /Users/x/old/node_modules/.bin/vite"
    }
    let chronological = Array(periodLines.reversed())      // oldest first: 100 days, 40 days, 6 days, 3.5 days, 30 h, 2 h
    try? ((Array(chronological[0..<2]) + filler + Array(chronological[2...])).joined(separator: "\n") + "\n").write(to: periodLog, atomically: true, encoding: .utf8)
    GuardHistory.useLog(at: periodLog)
    func inPeriod(_ hours: Int) -> [Int] {
        let begin = hours == 24 ? now.addingTimeInterval(-86_400)
            : (calendar.date(byAdding: .day, value: -(hours / 24), to: calendar.startOfDay(for: now)) ?? now)
        return ages.indices.filter { now.addingTimeInterval(-ages[$0] * 3_600) >= begin }
    }
    for (name, hours) in [("last 24 hours", 24), ("last 3 days", 72), ("last 7 days", 168), ("last 90 days", 2_160)] {
        let loaded = GuardHistory.load(since: GuardHistory.periodStart(hours: hours, now: now))
        let wanted = Set(inPeriod(hours).map { 7_000 + $0 })
        let got = Set(loaded.entries.compactMap(\.pid).filter { $0 < 8_000 })     // the filler is not what is being counted
        check("the \(name) holds exactly the alerts inside it", got == wanted && !wanted.isEmpty,
              "read \(got.sorted()), wanted \(wanted.sorted()), \(loaded.coverage.bytesRead) bytes")
    }
    // an entry screen looks a row up in the same period the list showed (GuardEntryScreen): every row of every
    // period must be found again by its id in that period's read, including a group that straddles the period's start
    for hours in [24, 72, 168, 2_160] {
        let read = GuardHistory.load(since: GuardHistory.periodStart(hours: hours, now: now))
        let ids = read.days(scope: .all, search: "").flatMap { $0.rows.map(\.id) }
        let lost = ids.filter { read.row(id: $0) == nil }
        check("every row of the last \(hours) hours opens from that period's read", lost.isEmpty && !ids.isEmpty,
              "\(lost.count) of \(ids.count) rows not found")
    }
    let shortRead = GuardHistory.load(since: GuardHistory.periodStart(hours: 24, now: now)).coverage.bytesRead
    let longRead = GuardHistory.load(since: GuardHistory.periodStart(hours: 2_160, now: now)).coverage.bytesRead
    check("a short period reads less of the log than a long one", shortRead < longRead, "24 hours \(shortRead) bytes, 90 days \(longRead) bytes")
    let panel = GuardLogParser.recentEvents(fromLog: periodLog, within: 86_400, limit: 50, after: nil)
    check("the menu-bar panel's last 24 hours and the screen's are the same alerts",
          Set(panel.compactMap(\.pid)) == Set(GuardHistory.load(since: GuardHistory.periodStart(hours: 24, now: Date())).entries.compactMap(\.pid)) && panel.count == 1,
          "panel \(panel.compactMap(\.pid).sorted())")
    exit(failed ? 1 : 0)
}
