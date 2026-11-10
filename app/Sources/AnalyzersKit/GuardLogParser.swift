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

    public static func parseLine(_ line: String) -> GuardEvent? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 4,
              let date = timestampFormat.date(from: "\(fields[0]) \(fields[1])")
        else { return nil }

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
            let level = Int(line.range(of: #"level (\d+)"#, options: .regularExpression)
                .map { String(line[$0]).replacingOccurrences(of: "level ", with: "") } ?? "") ?? 0
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
                                    within interval: TimeInterval = 86_400,
                                    limit: Int = 6,
                                    after clearedAt: Date? = nil) -> [GuardEvent] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let cutoff = max(Date().addingTimeInterval(-interval), clearedAt ?? .distantPast)

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

    /// Full-depth parse for the Logs pane (no per-pid spike dedupe — the log
    /// screen shows everything; the menu keeps the collapsed view).
    public static func allEvents(fromLog url: URL,
                                 within interval: TimeInterval = 90 * 86_400,
                                 limit: Int = 500) -> [GuardEvent] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let cutoff = Date().addingTimeInterval(-interval)
        return text.split(separator: "\n").suffix(2000)
            .compactMap { parseLine(String($0)) }
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
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
