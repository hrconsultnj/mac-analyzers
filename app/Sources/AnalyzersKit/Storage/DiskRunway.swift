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
        daysToFull > 42 ? "~\(Int((daysToFull / 7).rounded())) weeks" : "~\(Int(daysToFull.rounded())) days"
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
            guard line.hasPrefix("Free space now:"), let date,
                  let range = line.range(of: #"([\d.]+)Gi"#, options: .regularExpression),
                  let gib = Double(line[range].dropLast(2)) else { continue }
            points.append((date.timeIntervalSince1970 / 86_400, gib))
        }
        return points
    }

    /// The runway for these points, or nil when there is no honest forecast.
    public static func forecast(_ points: [(day: Double, freeGiB: Double)]) -> DiskRunway? {
        guard points.count >= 5, let minT = points.map(\.day).min(), let maxT = points.map(\.day).max(),
              maxT - minT >= 7 else { return nil }
        let n = Double(points.count)
        let sumT = points.map(\.day).reduce(0, +)
        let sumF = points.map(\.freeGiB).reduce(0, +)
        let sumTF = points.map { $0.day * $0.freeGiB }.reduce(0, +)
        let sumTT = points.map { $0.day * $0.day }.reduce(0, +)
        let denom = n * sumTT - sumT * sumT
        guard denom != 0 else { return nil }
        let slope = (n * sumTF - sumT * sumF) / denom               // GiB per day
        guard slope < -0.01 else { return nil }                      // flat or up is no story
        guard let latest = points.max(by: { $0.day < $1.day }) else { return nil }
        let days = latest.freeGiB / abs(slope)
        guard days.isFinite, days > 0 else { return nil }
        return DiskRunway(daysToFull: days, points: points.count)
    }

    public static func current() -> DiskRunway? { forecast(series()) }
}
