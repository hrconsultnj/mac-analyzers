import Foundation

/// One bar of a Trends chart: an hour or a day, with what the guard and the cleaners did in it.
public struct TrendBucket: Identifiable, Sendable, Equatable {
    public let start: Date
    public var kills = 0
    public var spikes = 0
    public var other = 0
    public var freedMB = 0
    public var removedBytes: Int64 = 0
    public var id: Date { start }
    public var events: Int { kills + spikes + other }
}

/// Puts a period's events into the buckets its chart draws: the last 24 hours as 24 clock hours ending with the
/// current one, a longer period as one bucket per calendar day from the day the period begins through today (the
/// period begins at the start of its first day, so that day is whole and today is the part so far). Everything inside
/// the period lands in a bucket; nothing is dropped and nothing is counted twice.
public enum TrendBuckets {

    public static func starts(for period: ReportPeriod, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        switch period.bucket {
        case .hour:
            guard let thisHour = calendar.dateInterval(of: .hour, for: now)?.start else { return [] }
            return (0..<24).reversed().compactMap { calendar.date(byAdding: .hour, value: -$0, to: thisHour) }
        case .day:
            var day = calendar.startOfDay(for: period.start(now: now, calendar: calendar))
            let last = calendar.startOfDay(for: now)
            var found: [Date] = []
            while day <= last {
                found.append(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return found
        }
    }

    /// The bucket a moment belongs to: the latest bucket start at or before it, and the first bucket for a moment
    /// before them all (the part of the first hour that the rolling 24 hours reaches back into).
    private static func index(of date: Date, in starts: [Date]) -> Int? {
        guard !starts.isEmpty else { return nil }
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= date { low = mid } else { high = mid - 1 }
        }
        return low
    }

    public static func make(period: ReportPeriod, now: Date = Date(), calendar: Calendar = .current,
                            events: [GuardEvent],
                            freed: [(date: Date, mb: Int)] = [],
                            removed: [(date: Date, bytes: Int64)] = []) -> [TrendBucket] {
        let starts = starts(for: period, now: now, calendar: calendar)
        // what happened before the period begins is not in it, even where the first bucket (a whole hour) reaches back
        let begin = period.start(now: now, calendar: calendar)
        var buckets = starts.map { TrendBucket(start: $0) }
        for event in events where event.date >= begin {
            guard let at = index(of: event.date, in: starts) else { continue }
            switch event.kind {
            case .killed:
                buckets[at].kills += 1
                buckets[at].freedMB += event.residentMB ?? 0
            case .spike: buckets[at].spikes += 1
            default: buckets[at].other += 1
            }
        }
        for item in freed where item.date >= begin {
            if let at = index(of: item.date, in: starts) { buckets[at].freedMB += item.mb }
        }
        for item in removed where item.date >= begin {
            if let at = index(of: item.date, in: starts) { buckets[at].removedBytes += item.bytes }
        }
        return buckets
    }
}
