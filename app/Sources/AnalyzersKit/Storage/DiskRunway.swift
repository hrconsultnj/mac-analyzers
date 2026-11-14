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
        if daysToFull < 1 { return "under a day" }
        if daysToFull > 42 { return "~\(Int((daysToFull / 7).rounded())) weeks" }
        let days = Int(daysToFull.rounded())
        return "~\(days) \(days == 1 ? "day" : "days")"
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
    ///
    /// How it is worked out, so one odd reading cannot drive it:
    ///  1. a sudden fall is told as what happened, and only when it happened between two readings and
    ///     the NEWEST TWO agree (`confirmedFall`); a single low newest reading is not believed yet and is
    ///     left out; a fall that has recovered is no fall;
    ///  2. otherwise the line is the MEDIAN of the slopes between every pair of readings (Theil–Sen), so one
    ///     bad reading anywhere moves it by next to nothing; the last week's line decides when it is falling,
    ///     the whole log's when it is not;
    ///  3. a countdown of under 30 days is only given when the newest two readings sit on the line.
    public static func outlook(_ all: [(day: Double, freeGiB: Double)]) -> (runway: DiskRunway?, reason: String) {
        var points = all.sorted { $0.day < $1.day }
        let n = points.count
        guard n >= 5 else {
            return (nil, "A forecast needs figures from at least five cleanups; there \(n == 1 ? "is" : "are") \(n) so far.")
        }
        if let fall = confirmedFall(points) {
            return (nil, "Free space fell from about \(Int(fall.before.rounded())) GB to \(Int(fall.now.rounded())) GB between two cleanups, and the latest two figures agree. A forecast from the earlier days would be wrong, so none is shown. Clearing space is the answer for now.")
        }
        // The newest figure far below the usual of the others (a fall seen once, or one that partly recovered): whatever
        // else is found, "steady or rising" would be false, so that is what is said instead
        let others = points.dropLast().map(\.freeGiB).sorted()
        let usual = others[others.count / 2]
        let newestFarBelow = (points.last?.freeGiB ?? usual) < usual * 0.5 && usual - (points.last?.freeGiB ?? usual) >= 10
        // one low NEWEST reading is not believed until a second one agrees: the forecast is made without it
        if points.count >= 3 {
            let last = points[points.count - 1], before = points[points.count - 2]
            let beforeThat = points.count >= 3 ? points[points.count - 3].freeGiB : before.freeGiB
            let previousAlsoFell = before.freeGiB < beforeThat * 0.8      // a fall in two steps is a fall
            if last.freeGiB < before.freeGiB * 0.5, before.freeGiB - last.freeGiB >= 10, !previousAlsoFell { points.removeLast() }
        }
        points = withoutRecoveredDips(points)
        let minT = points.map(\.day).min() ?? 0, maxT = points.map(\.day).max() ?? 0
        let span = Int((maxT - minT).rounded(.down))
        guard maxT - minT >= 7 else {
            return (nil, "A forecast needs figures spread over at least a week; these cover \(span) \(span == 1 ? "day" : "days").")
        }
        guard let latest = points.last else { return (nil, "") }
        let steady = "Free space has been steady or rising over \(span) days, so there is nothing to count down."

        func result(_ fit: [(day: Double, freeGiB: Double)], _ words: String) -> (runway: DiskRunway?, reason: String)? {
            guard let line = line(of: fit), line.slope < -0.01 else { return nil }
            let days = latest.freeGiB / abs(line.slope)
            guard days.isFinite, days > 0 else { return nil }
            if days < 30 {
                // an urgent countdown needs the newest two readings on the line, not one that strayed
                for p in points.suffix(2) where abs(p.freeGiB - (line.slope * p.day + line.intercept)) > max(5, 0.15 * p.freeGiB) {
                    return (nil, "The newest free-space figures don't follow the trend yet, so no countdown is shown. Preview again to add one.")
                }
            }
            return (DiskRunway(daysToFull: days, points: fit.count), words)
        }
        // the last week decides when it is falling: a long trend that is still rising must not hide a disk that is not
        let recent = points.filter { $0.day >= maxT - 7 }
        if recent.count >= 3, let from = recent.map(\.day).min(), maxT - from >= 1 {
            let window = Int((maxT - from).rounded(.up))
            if let found = result(recent, "Worked out from the last \(window) \(window == 1 ? "day" : "days") (\(recent.count) cleanups' figures).") {
                return found
            }
        }
        if let found = result(points, "Worked out from \(points.count) cleanups' free-space figures over \(span) days.") { return found }
        if newestFarBelow {
            return (nil, "The newest figure is far below the others, so no forecast is made from it yet. Preview again to confirm.")
        }
        return (nil, steady)
    }

    /// Readings that dipped far below the fortnight's usual and then came back (a big build, a cleanup that
    /// followed) are an episode that is over, not a trend: they are left out. A dip that has not recovered stays.
    static func withoutRecoveredDips(_ ordered: [(day: Double, freeGiB: Double)]) -> [(day: Double, freeGiB: Double)] {
        guard let newest = ordered.last?.day else { return ordered }
        let recent = ordered.filter { $0.day >= newest - 14 }.map(\.freeGiB).sorted()
        guard recent.count >= 5 else { return ordered }
        let usual = recent[recent.count / 2]
        return ordered.enumerated().filter { index, point in
            guard point.freeGiB < usual * 0.5, point.day >= newest - 14 else { return true }
            let recovered = ordered[(index + 1)...].contains { $0.freeGiB >= usual * 0.8 }
            return !recovered
        }.map(\.element)
    }

    /// A sudden fall that has two readings behind it: the reading before it, then two that are both lower
    /// (the newest under half of it, at least 10 GiB less) and not climbing back. A single low reading, or a
    /// fall that has already recovered, is not one.
    static func confirmedFall(_ ordered: [(day: Double, freeGiB: Double)]) -> (before: Double, now: Double)? {
        guard ordered.count >= 5 else { return nil }
        let c = ordered[ordered.count - 3].freeGiB, a = ordered[ordered.count - 2].freeGiB, b = ordered[ordered.count - 1].freeGiB
        // the newest two are both well below the reading before them, and the newest is not climbing back
        guard a < c * 0.8, b < c * 0.5, c - b >= 10, b <= a + max(5, 0.25 * a) else { return nil }
        return (c, b)
    }

    /// The robust line through the points: the median of the slopes between every pair of readings, and the
    /// median intercept it leaves (Theil–Sen). nil when no two readings are on different days.
    static func line(of points: [(day: Double, freeGiB: Double)]) -> (slope: Double, intercept: Double)? {
        var slopes: [Double] = []
        for i in points.indices {
            for j in points.indices where j > i && abs(points[j].day - points[i].day) > 0.01 {
                slopes.append((points[j].freeGiB - points[i].freeGiB) / (points[j].day - points[i].day))
            }
        }
        guard !slopes.isEmpty else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        let slope = median(slopes)
        return (slope, median(points.map { $0.freeGiB - slope * $0.day }))
    }

    public static func current() -> DiskRunway? { forecast(series()) }
}
