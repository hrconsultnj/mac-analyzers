import SwiftUI
import AnalyzersKit

/// Memory Guard's history for the window the person chose. Reading the log is
/// done off the main thread through the shared load coordinator.
@MainActor @Observable
final class GuardHistoryModel {

    /// The periods the menu offers. The raw value is the length in hours (what is remembered and what a link carries).
    enum Window: Int, CaseIterable, Identifiable {
        case day = 24
        case threeDays = 72
        case week = 168
        case quarter = 2_160
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .day: Names.Guard.last24
            case .threeDays: Names.Guard.last3
            case .week: Names.Guard.last7
            case .quarter: Names.Guard.last90
            }
        }

        /// Where the period begins (`GuardHistory.periodStart`: the last 24 hours back from now, the others from the start of that day).
        func start(now: Date = Date()) -> Date { GuardHistory.periodStart(hours: rawValue, now: now) }
    }

    /// The person's last choice, kept between launches; nothing stored means the last 24 hours.
    private static let choiceKey = "guard.periodHours"
    static func savedWindow(_ defaults: UserDefaults = .standard) -> Window {
        Window(rawValue: defaults.integer(forKey: choiceKey)) ?? .day
    }

    private(set) var history = GuardHistory.empty {
        didSet { loads += 1 }
    }
    private(set) var hasLoaded = false
    @ObservationIgnored private var loads = 0
    @ObservationIgnored private var memo: (key: String, days: [GuardHistory.Day])?
    /// How many days are shown, per filter (scope, search, load). A filter that has
    /// not been paged shows its first page; "Show Older" adds the next whole days.
    private var taken: [String: Int] = [:]
    @ObservationIgnored private var currentKey = ""
    var window: Window = GuardHistoryModel.savedWindow() {
        didSet { UserDefaults.standard.set(window.rawValue, forKey: Self.choiceKey) }
    }

    /// The history for a window, read once and shared: the list and every
    /// entry screen opened from it use the same read (about a second on a
    /// 90-day log, off the main actor), not one each. `force` is the Refresh button.
    static func history(days: Int, force: Bool = false) async -> GuardHistory? {
        await LoadCoordinator.shared.value(key: "guard.history.\(days)", ttl: force ? 0 : 60) {
            GuardHistory.load(days: days)
        }
    }

    /// The history for a period the menu offers: read only back to where the period begins.
    static func history(window: Window, force: Bool = false) async -> GuardHistory? {
        await LoadCoordinator.shared.value(key: "guard.history.hours.\(window.rawValue)", ttl: force ? 0 : 60) {
            GuardHistory.load(since: window.start())
        }
    }

    /// The days for a tab and a search, grouped once: grouping 60,000 entries
    /// takes a fifth of a second, which a redraw must not pay again.
    func days(scope: GuardHistory.Scope, search: String) -> [GuardHistory.Day] {
        let key = "\(loads)|\(scope.rawValue)|\(search)"
        currentKey = key
        if let memo, memo.key == key { return memo.days }
        let days = history.days(scope: scope, search: search)
        memo = (key, days)
        return days
    }

    /// The part of `days` to show now: the newest whole days, at most one page of
    /// rows per step, plus what is left behind.
    struct Page {
        let shown: [GuardHistory.Day]
        let olderDays: Int
        let olderRows: Int
        var isComplete: Bool { olderDays == 0 }
    }

    func page(of days: [GuardHistory.Day]) -> Page {
        let count = taken[currentKey] ?? GuardHistory.pageEnd(of: days, from: 0)
        let end = min(count, days.count)
        let older = days[end...]
        return Page(shown: Array(days[..<end]), olderDays: older.count, olderRows: older.reduce(0) { $0 + $1.rows.count })
    }

    func showOlder(in days: [GuardHistory.Day]) {
        let now = min(taken[currentKey] ?? GuardHistory.pageEnd(of: days, from: 0), days.count)
        taken[currentKey] = GuardHistory.pageEnd(of: days, from: now)
    }

    func refresh(force: Bool = false) async {
        guard let loaded = await Self.history(window: window, force: force), !Task.isCancelled else { return }
        history = loaded
        hasLoaded = true
    }
}
