import Foundation

/// How far back a screen looks: the one period type behind Trends' menu and Memory Guard's menu, so both offer the
/// same six and a period means the same thing everywhere. The raw value is the length in hours (what each screen
/// remembers and what a link carries).
///
/// A period begins where `GuardHistory.periodStart` says: the last 24 hours begins on the hour (the current clock hour and
/// the 23 before it), "Last N Days" at the start of the day N-1 days back (N days counting today). What a chart draws is
/// one bar per `bucket`: 24 hourly bars for the last 24 hours, N daily bars for N days.
public enum ReportPeriod: Int, CaseIterable, Identifiable, Codable, Sendable {
    case day = 24
    case threeDays = 72
    case week = 168
    case fortnight = 336
    case month = 720
    case quarter = 2_160

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .day: Names.Period.last24
        case .threeDays: Names.Period.last3
        case .week: Names.Period.last7
        case .fortnight: Names.Period.last14
        case .month: Names.Period.last30
        case .quarter: Names.Period.last90
        }
    }

    /// The short name a link carries: `24h`, `3d`, `7d`, `30d`, `90d`.
    public var linkName: String { self == .day ? "24h" : "\(rawValue / 24)d" }

    public init?(linkName: String) {
        guard let found = Self.allCases.first(where: { $0.linkName == linkName }) else { return nil }
        self = found
    }

    /// For a sentence: "in the last 7 days".
    public var phrase: String { "the " + title.lowercased() }

    /// Where the period begins.
    public func start(now: Date = Date(), calendar: Calendar = .current) -> Date {
        GuardHistory.periodStart(hours: rawValue, now: now, calendar: calendar)
    }

    public enum Bucket: Sendable {
        case hour, day
        public var component: Calendar.Component { self == .hour ? .hour : .day }
    }

    /// Hourly for the last 24 hours, daily for everything longer.
    public var bucket: Bucket { self == .day ? .hour : .day }

    /// A period remembered under `key` (hours), or `fallback` when nothing is stored. A length that is not
    /// offered becomes the nearest longer one.
    public static func saved(key: String, fallback: ReportPeriod, defaults: UserDefaults = .standard) -> ReportPeriod {
        let hours = defaults.integer(forKey: key)
        guard hours > 0 else { return fallback }
        return nearest(atLeast: hours) ?? .quarter
    }

    public static func nearest(atLeast hours: Int) -> ReportPeriod? {
        allCases.first { $0.rawValue >= hours }
    }

    public func remember(key: String, defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: key)
    }
}
