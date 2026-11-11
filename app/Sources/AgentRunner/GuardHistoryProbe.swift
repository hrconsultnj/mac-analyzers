import Foundation
import AnalyzersKit

// `agent-runner --probe-guard-history [--scope all|stopped|alerts|reports] [--search text]`
// prints Memory Guard's history exactly as the screen groups it, from the real
// guard.log: a day header with its total, then one line per row. Nothing is
// written and no process is touched.

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

func probeGuardHistory(_ args: [String]) -> Never {
    func value(after flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
    let scope: GuardHistory.Scope = switch value(after: "--scope") {
    case "stopped": .stopped
    case "alerts": .alerts
    case "reports": .crisisReports
    default: .all
    }
    let started = Date()
    let history = GuardHistory.load()
    let loadSeconds = Date().timeIntervalSince(started)
    let days = history.days(scope: scope, search: value(after: "--search") ?? "")
    let now = Date()
    for day in days {
        print("\(day.title(now: now).uppercased())   (\(day.summary))")
        for row in day.rows.prefix(args.contains("--all") ? Int.max : 6) {
            print("    " + pad(row.timeText, 20) + pad(row.title, 62) + row.outcome)
        }
        if !args.contains("--all"), day.rows.count > 6 { print("    … and \(day.rows.count - 6) more rows") }
    }
    let rows = days.reduce(0) { $0 + $1.rows.count }
    let entries = days.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.count } }
    let ids = days.flatMap { $0.rows.map(\.id) }
    // rows a List would load at once, per window, after folding (the newest-first full set)
    let cal = Calendar.current
    print("rows in the list per window: " + [7, 30, 90].map { d in
        let cutoff = cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: Date())) ?? Date()
        return "\(d) days \(days.filter { $0.day >= cutoff }.reduce(0) { $0 + $1.rows.count })"
    }.joined(separator: " | ") + "; busiest single day \(days.map(\.rows.count).max() ?? 0)")
    // the list loads a page at a time: whole days, at most pageRows rows per step
    func steps(_ label: String, _ list: [GuardHistory.Day]) {
        var start = 0, step = 1, total = 0
        var line: [String] = []
        while start < list.count {
            let end = GuardHistory.pageEnd(of: list, from: start)
            let added = list[start..<end].reduce(0) { $0 + $1.rows.count }
            total += added
            line.append("step \(step): +\(end - start) days, +\(added) rows (\(total) shown, to \(list[end - 1].day.formatted(.dateTime.month(.abbreviated).day())))")
            start = end; step += 1
            if step > 12 { line.append("…"); break }
        }
        print("paging, \(label): \(list.count) days, \(list.reduce(0) { $0 + $1.rows.count }) rows\n    " + (line.isEmpty ? "nothing" : line.joined(separator: "\n    ")))
    }
    steps("all events, 90 days", days)
    let sevenCut = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date())) ?? Date()
    steps("all events, 7 days", days.filter { $0.day >= sevenCut })
    for scope in [GuardHistory.Scope.stopped, .alerts] { steps("\(scope.title), 90 days", history.days(scope: scope)) }
    for term in ["node", "next"] { steps("search \"\(term)\" over the whole 90 days", history.days(scope: .all, search: term)) }
    let biggest = days.map { $0.rows.count }.max() ?? 0
    print("largest update: \(maxStep(days)) rows (a day is never split; busiest single day \(biggest))")
    print("days: \(days.count), rows: \(rows), entries: \(entries), unique row ids: \(Set(ids).count)")

    // how far back the history really goes, and what it holds per period
    let c = history.coverage
    print("\nread \(c.bytesRead / 1024) KB in \(String(format: "%.2f", loadSeconds)) s: \(c.eventCount) events back to \(c.oldest.map { $0.formatted() } ?? "nothing") (window reached: \(c.reachedWindow))")
    func count(_ kind: GuardEntry.Kind, since days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return history.entries.filter { $0.kind == kind && $0.date >= cutoff }.count
    }
    print("per period (this reader): " + [7, 30, 90].map { d in
        "\(d) days: \(GuardEntry.Kind.allCases.map { "\($0.rawValue) \(count($0, since: d))" }.joined(separator: ", "))"
    }.joined(separator: " | "))
    // the same read as before: the last 2,000 lines only
    if let url = EngineLog.guardLog.url, let text = try? String(contentsOf: url, encoding: .utf8) {
        let capped = text.split(separator: "\n").suffix(2000).compactMap { GuardLogParser.parseLine(String($0)) }
        print("the old 2,000-line read: \(capped.count) events back to \(capped.map(\.date).min().map { $0.formatted() } ?? "-"), \(capped.filter(\.isKill).count) stops")
    }
    // a crisis report as the entry screen reads it
    if let report = history.entries.last(where: { $0.kind == .crisisReport && $0.reportPath != nil }),
       let path = report.reportPath, let summary = CrisisReportSummary.read(path: path) {
        print("\nlatest crisis report on disk: \(summary.title)")
        print("  \(summary.headline)")
    }
    // what it printed, judged on the real log: row ids are unique, and a page never passes the rule
    // (a day is never split, so only a day that is itself bigger may)
    let unique = Set(ids).count == ids.count
    let paged = maxStep(days) <= max(GuardHistory.pageRows, biggest)
    print("self-check: row ids unique \(unique), pages within \(GuardHistory.pageRows) rows \(paged)")
    exit(unique && paged ? 0 : 1)
}

private func maxStep(_ list: [GuardHistory.Day]) -> Int {
    var start = 0, largest = 0
    while start < list.count {
        let end = GuardHistory.pageEnd(of: list, from: start)
        largest = max(largest, list[start..<end].reduce(0) { $0 + $1.rows.count })
        start = end
    }
    return largest
}
