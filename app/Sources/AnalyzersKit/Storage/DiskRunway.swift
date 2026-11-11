import Foundation

/// How long the free space on the boot volume lasts at the rate it has been falling:
/// a least-squares line through the "Free space now" figure each storage run printed,
/// dated by that run's banner. Honest thresholds: no forecast until five points span
/// a week, and only when the trend is actually downward.
///
/// The figures come from the WHOLE storage log (bounded at the same 32 MB reach as a run),
/// not the newest runs: a runway computed from the last twenty runs is a runway of the last
/// few days.
public struct DiskRunway: Sendable, Equatable {
    public let daysToFull: Double
    /// How many runs' figures it was computed from.
    public let points: Int

    public init(daysToFull: Double, points: Int) {
        self.daysToFull = daysToFull
        self.points = points
    }

    public var text: String {
        daysToFull < 1 ? "under a day" : daysToFull > 42 ? "~\(Int((daysToFull / 7).rounded())) weeks" : "~\(Int(daysToFull.rounded())) days"
    }
    public var isUrgent: Bool { daysToFull < 30 }

    /// (day number, free GiB) from the storage log, oldest first.
    public static func series(in log: URL = AnalyzersPaths.storageAutoCleanLog) -> [(day: Double, freeGiB: Double)] {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(WholeRun.reach) ? size - UInt64(WholeRun.reach) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var date: Date?
        var points: [(Double, Double)] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let banner = RunMatcher.banner(in: line) { date = RunDate.date(of: banner); continue }
            guard line.hasPrefix("Free space now:"), let date, let gib = freeGiB(in: line) else { continue }
            points.append((date.timeIntervalSince1970 / 86_400, gib))
        }
        return points
    }

    /// The free space a "Free space now: 512Mi avail (98% used)" line says, in GiB. `df -h` writes the
    /// unit it likes (Ki, Mi, Gi, Ti), and a comma-decimal locale writes "4,5Gi".
    public static func freeGiB(in line: String) -> Double? {
        guard let range = line.range(of: #"([\d.,]+)\s?([KMGT])i"#, options: .regularExpression) else { return nil }
        let text = String(line[range])
        guard let unit = text.last(where: { "KMGT".contains($0) }) ?? text.dropLast().last else { return nil }
        let number = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        let normalized = number.contains(".") ? number.replacingOccurrences(of: ",", with: "")
                                              : number.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        switch unit {
        case "K": return value / 1_048_576
        case "M": return value / 1024
        case "G": return value
        default: return value * 1024
        }
    }

    /// The runway for these points, or nil when there is no honest forecast.
    public static func forecast(_ points: [(day: Double, freeGiB: Double)]) -> DiskRunway? { outlook(points).runway }

    /// The runway, or why there is none: too few figures, too short a time, or a trend that is not
    /// falling. The sentence is the one the screen shows beside "No forecast".
    public static func outlook(_ points: [(day: Double, freeGiB: Double)]) -> (runway: DiskRunway?, reason: String) {
        let n = points.count
        guard n >= 5 else {
            return (nil, "A forecast needs figures from at least five cleanups; there \(n == 1 ? "is" : "are") \(n) so far.")
        }
        let minT = points.map(\.day).min() ?? 0, maxT = points.map(\.day).max() ?? 0
        let span = Int((maxT - minT).rounded(.down))
        guard maxT - minT >= 7 else {
            return (nil, "A forecast needs figures spread over at least a week; these cover \(span) \(span == 1 ? "day" : "days").")
        }
        guard let latest = points.max(by: { $0.day < $1.day }) else { return (nil, "") }
        // The RECENT slope decides when the last week is falling: a long trend that is still rising
        // (33 GiB free months ago, 124 a day ago) must not hide a disk that lost 110 GiB since.
        let recent = points.filter { $0.day >= maxT - 7 }
        if recent.count >= 3, let from = recent.map(\.day).min(), maxT - from >= 1,
           let slope = slope(of: recent), slope < -0.01 {
            let days = latest.freeGiB / abs(slope)
            if days.isFinite, days > 0 {
                let window = Int((maxT - from).rounded(.up))
                return (DiskRunway(daysToFull: days, points: recent.count),
                        "Worked out from the last \(window) \(window == 1 ? "day" : "days") (\(recent.count) cleanups' figures), which are falling faster than the long trend.")
            }
        }
        let steady = "Free space has been steady or rising over \(span) days, so there is nothing to count down."
        guard let slope = slope(of: points), slope < -0.01 else { return (nil, steady) }
        let days = latest.freeGiB / abs(slope)
        guard days.isFinite, days > 0 else { return (nil, steady) }
        return (DiskRunway(daysToFull: days, points: n), "Worked out from \(n) cleanups' free-space figures over \(span) days.")
    }

    /// GiB per day of the least-squares line through the points, nil when they do not span time.
    static func slope(of points: [(day: Double, freeGiB: Double)]) -> Double? {
        let count = Double(points.count)
        let sumT = points.map(\.day).reduce(0, +)
        let sumF = points.map(\.freeGiB).reduce(0, +)
        let sumTF = points.map { $0.day * $0.freeGiB }.reduce(0, +)
        let sumTT = points.map { $0.day * $0.day }.reduce(0, +)
        let denom = count * sumTT - sumT * sumT
        guard denom != 0 else { return nil }
        return (count * sumTF - sumT * sumF) / denom
    }

    public static func current() -> DiskRunway? { forecast(series()) }
}
