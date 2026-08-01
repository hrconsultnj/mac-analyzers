import Foundation

/// One human-readable memory-guard event parsed from guard.log.
public struct GuardEvent: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case killed(reason: String)
        case spike(grewMB: Int)
        case warning
    }

    public let id: String
    public let date: Date
    public let kind: Kind
    public let processName: String
    public let pid: Int?
    public let residentMB: Int?
    public let raw: String

    public init(id: String, date: Date, kind: Kind, processName: String,
                pid: Int?, residentMB: Int?, raw: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.processName = processName
        self.pid = pid
        self.residentMB = residentMB
        self.raw = raw
    }

    public var isKill: Bool { if case .killed = kind { return true }; return false }

    /// "6.1 GB" style resident-size string.
    public var residentText: String? {
        residentMB.map { String(format: "%.1f GB", Double($0) / 1024) }
    }

    /// Full human sentence for the row, without the timestamp.
    public var summary: String {
        switch kind {
        case .killed(let reason):
            return "\(processName) killed — was \(residentText ?? "?") (\(reason))"
        case .spike(let grew):
            let grewText = String(format: "%.1f GB", Double(grew) / 1024)
            return "\(processName) climbing — at \(residentText ?? "?") (+\(grewText))"
        case .warning:
            return processName
        }
    }

    /// Human name from the glossary ("Next.js dev server"), else the raw one.
    public var friendlyName: String {
        ProcessGlossary.friendlyName(for: processName) ?? processName
    }

    /// Two-line row support: TITLE = friendly what-happened,
    /// SUBTITLE = raw identity + mechanics (time appended by the view).
    public var title: String {
        switch kind {
        case .killed:
            return "\(friendlyName) killed — was \(residentText ?? "?")"
        case .spike(let grew):
            let grewText = String(format: "%.1f GB", Double(grew) / 1024)
            return "\(friendlyName) climbing — at \(residentText ?? "?") (+\(grewText))"
        case .warning:
            return processName
        }
    }

    public var subtitle: String {
        var parts: [String] = []
        if friendlyName != processName { parts.append(processName) }
        if let pid { parts.append("pid \(pid)") }
        if case .killed(let reason) = kind { parts.append(reason) }
        return parts.joined(separator: " · ")
    }
}

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
        var warnings: [GuardEvent] = []
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
            case .warning:
                warnings.append(event)
            }
        }

        let spikes = latestSpike.filter { !killedPIDs.contains($0.key) }.map(\.value)
        return (kills + warnings + spikes)
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
