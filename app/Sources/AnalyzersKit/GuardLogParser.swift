import Foundation

/// Parser for guard.log lines. Swift port of the SwiftBar plugin's awk logic:
///   2026-07-31 16:15:11 KILLED [hard-cap 6144MB] pid=30637 rss=6200MB  name…
///   2026-07-31 15:48:35 SPIKE pid=30637 +687MB now 5024MB  name…
public enum GuardLogParser {

    private static let timestampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// "yyyy-MM-dd HH:mm:ss" (local time) read straight from the line's first
    /// 19 characters. A formatter costs about 60 µs a line, which is four
    /// seconds across a 90-day log; this is about a microsecond.
    static func timestamp(of line: String) -> Date? {
        var chars = line.utf8.prefix(19).makeIterator()
        var bytes: [UInt8] = []
        bytes.reserveCapacity(19)
        while let next = chars.next() { bytes.append(next) }
        guard bytes.count == 19, bytes[4] == 45, bytes[7] == 45, bytes[10] == 32,
              bytes[13] == 58, bytes[16] == 58 else { return nil }
        func number(_ range: Range<Int>) -> Int32? {
            var value: Int32 = 0
            for index in range {
                guard bytes[index] >= 48, bytes[index] <= 57 else { return nil }
                value = value * 10 + Int32(bytes[index] - 48)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19)
        else { return nil }
        var parts = tm()
        parts.tm_year = year - 1900
        parts.tm_mon = month - 1
        parts.tm_mday = day
        parts.tm_hour = hour
        parts.tm_min = minute
        parts.tm_sec = second
        parts.tm_isdst = -1
        let seconds = mktime(&parts)
        return seconds == -1 ? nil : Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public static func parseLine(_ line: String) -> GuardEvent? {
        guard let date = timestamp(of: line) else { return nil }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 4 else { return nil }

        let token = fields[2]
        switch token {
        case "KILLED":
            var reason = "guard rule"
            if let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"), open < close {
                reason = String(line[line.index(after: open)..<close])
                if reason.hasPrefix("hard-cap") {
                    let capMB = Int(reason.dropFirst("hard-cap".count)
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "MB", with: "")) ?? 0
                    reason = capMB > 0
                        ? "over the \(Int((Double(capMB) / 1024).rounded())) GB cap"
                        : "over the RAM cap"
                } else if reason.contains("pressure") || reason.contains("critical") {
                    reason = "critical memory pressure"
                }
            }
            var pid: Int?
            var rss: Int?
            var nameStart: Int?
            for (i, f) in fields.enumerated() {
                if f.hasPrefix("pid=") { pid = Int(f.dropFirst(4)) }
                if f.hasPrefix("rss=") {
                    rss = Int(f.dropFirst(4).replacingOccurrences(of: "MB", with: ""))
                    nameStart = i + 1
                }
            }
            guard let start = nameStart, start < fields.count else { return nil }
            let name = fields[start...].joined(separator: " ")
            return GuardEvent(id: line, date: date, kind: .killed(reason: reason),
                              processName: name, pid: pid, residentMB: rss, raw: line)

        case "KILL-FAIL":
            // "KILL-FAIL pid=N already gone": the guard tried and the process had ended
            let pid = fields.first { $0.hasPrefix("pid=") }
                .flatMap { Int($0.dropFirst(4)) }
            return GuardEvent(id: line, date: date, kind: .stopFailed,
                              processName: "process", pid: pid, residentMB: nil, raw: line)

        case "SPIKE":
            guard fields.count >= 8, fields[3].hasPrefix("pid=") else { return nil }
            let pid = Int(fields[3].dropFirst(4))
            let grew = Int(fields[4].replacingOccurrences(of: "MB", with: "")
                .replacingOccurrences(of: "+", with: "")) ?? 0
            let now = Int(fields[6].replacingOccurrences(of: "MB", with: "")) ?? 0
            let name = fields[7...].joined(separator: " ")
            return GuardEvent(id: line, date: date, kind: .spike(grewMB: grew),
                              processName: name, pid: pid, residentMB: now, raw: line)

        case "PRESSURE", "PRESSURE-CRITICAL":
            // "PRESSURE warning (level 2)" · "PRESSURE CRITICAL (level 4)"
            // · "PRESSURE-CRITICAL (kill disabled)"
            let rest = fields[3...].joined(separator: " ")
            // "level N": a plain search, not a regular expression — pressure lines
            // are most of a long log
            let level = line.range(of: "level ").map {
                Int(line[$0.upperBound...].prefix { $0.isNumber }) ?? 0
            } ?? 0
            let kind: GuardEvent.Kind
            if token == "PRESSURE-CRITICAL" || rest.hasPrefix("CRITICAL") {
                kind = .pressureCritical(level: max(level, 4),
                                         killDisabled: line.contains("kill disabled"))
            } else {
                kind = .pressureWarning(level: max(level, 2))
            }
            return GuardEvent(id: line, date: date, kind: kind,
                              processName: "system memory", pid: nil,
                              residentMB: nil, raw: line)

        case "CAP-EXCEEDED":
            // "CAP-EXCEEDED (kill disabled) pid=N rss=NMB  name…"
            var pid: Int?
            var rss: Int?
            var nameStart: Int?
            for (i, f) in fields.enumerated() {
                if f.hasPrefix("pid=") { pid = Int(f.dropFirst(4)) }
                if f.hasPrefix("rss=") {
                    rss = Int(f.dropFirst(4).replacingOccurrences(of: "MB", with: ""))
                    nameStart = i + 1
                }
            }
            let name = nameStart.flatMap { $0 < fields.count ? fields[$0...].joined(separator: " ") : nil } ?? "dev process"
            return GuardEvent(id: line, date: date,
                              kind: .capExceeded(killDisabled: line.contains("kill disabled")),
                              processName: name, pid: pid, residentMB: rss, raw: line)

        case "CPU-HOG":
            // "CPU-HOG sustained >=150% for 3 ticks: pid=N name…; "
            let pct = Int(line.range(of: #">=(\d+)%"#, options: .regularExpression)
                .map { String(line[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ">=%")) } ?? "") ?? 0
            let ticks = Int(line.range(of: #"for (\d+) ticks"#, options: .regularExpression)
                .map { String(line[$0]).components(separatedBy: " ")[1] } ?? "") ?? 0
            var pid: Int?
            var name = "process"
            if let colon = line.range(of: "ticks: ") {
                let tail = String(line[colon.upperBound...])
                let parts = tail.split(separator: " ", maxSplits: 1)
                if let first = parts.first, first.hasPrefix("pid=") { pid = Int(first.dropFirst(4)) }
                if parts.count > 1 {
                    name = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "; "))
                }
            }
            return GuardEvent(id: line, date: date, kind: .cpuHog(pct: pct, ticks: ticks),
                              processName: name, pid: pid, residentMB: nil, raw: line)

        case "FORENSICS":
            // "FORENSICS written: /path/to/guard-critical-HHMMSS.log"
            let path = fields.count > 4 ? fields[4...].joined(separator: " ") : ""
            return GuardEvent(id: line, date: date, kind: .forensics(path: path),
                              processName: "forensics", pid: nil, residentMB: nil, raw: line)

        case "WARNING", "CRITICAL":
            let rest = fields[3...].joined(separator: " ")
            return GuardEvent(id: line, date: date, kind: .warning,
                              processName: rest, pid: nil, residentMB: nil, raw: line)

        default:
            return nil
        }
    }

    /// Recent events, clutter-collapsed the same way the SwiftBar plugin does:
    /// kills always show; only the LATEST spike per pid shows, and spikes from
    /// pids that were later killed are dropped. Newest first.
    public static func recentEvents(fromLog url: URL,
                                    since start: Date = GuardHistory.periodStart(hours: 24),
                                    limit: Int = 6,
                                    after clearedAt: Date? = nil) -> [GuardEvent] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let cutoff = max(start, clearedAt ?? .distantPast)

        var kills: [GuardEvent] = []
        var others: [GuardEvent] = []
        var latestSpike: [Int: GuardEvent] = [:]
        var killedPIDs: Set<Int> = []

        for line in text.split(separator: "\n").suffix(600) {
            guard let event = parseLine(String(line)), event.date >= cutoff else { continue }
            switch event.kind {
            case .killed:
                kills.append(event)
                if let pid = event.pid { killedPIDs.insert(pid) }
            case .spike:
                if let pid = event.pid { latestSpike[pid] = event }
            default:
                others.append(event)
            }
        }

        let spikes = latestSpike.filter { !killedPIDs.contains($0.key) }.map(\.value)
        return (kills + others + spikes)
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// Every event in the window, newest first, read back from the end of the
    /// log (and its rotated copy) to the cutoff — never a fixed number of
    /// lines, which is a different number of days on every Mac. `limit`, when
    /// given, keeps only that many of the newest events.
    ///
    /// Blocking; call it off the main actor.
    public static func allEvents(fromLog url: URL,
                                 within interval: TimeInterval = 90 * 86_400,
                                 limit: Int? = nil) -> [GuardEvent] {
        allEvents(fromLog: url, since: Date().addingTimeInterval(-interval), limit: limit)
    }

    /// The same from a date on: the log is read backwards only as far as `start`, so a short period costs a short read.
    public static func allEvents(fromLog url: URL, since start: Date, limit: Int? = nil) -> [GuardEvent] {
        let reading = GuardLogReader.read(url, since: start)
        let events = reading.lines.compactMap { parseLine($0) }
            .sorted { $0.date > $1.date }
        return limit.map { Array(events.prefix($0)) } ?? events
    }

    public static func killsToday(fromLog url: URL, after clearedAt: Date? = nil) -> Int {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return 0 }
        let today = timestampFormat.string(from: Date()).prefix(10)
        let floor = clearedAt ?? .distantPast
        return text.split(separator: "\n")
            .filter { $0.hasPrefix(today) && $0.contains(" KILLED ") }
            .compactMap { parseLine(String($0)) }
            .filter { $0.date > floor }
            .count
    }
}
