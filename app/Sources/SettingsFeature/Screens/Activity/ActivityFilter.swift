import AnalyzersKit
import Foundation
import Observation

/// What the person has chosen to look at in Activity, kept for the session:
/// the scope, and which days they opened or closed. It lives apart from the
/// view so a link (`activity:failed`) can set the scope before the screen exists.
@MainActor @Observable
final class ActivityFilter {
    static let shared = ActivityFilter()

    var scope: ActivityScope = .all
    var query = ""
    /// A day the person opened or closed by hand, by `ActivityDay.id`. A day not
    /// in here follows the default: the last week open, older days closed.
    private(set) var expansion: [String: Bool] = [:]

    /// Set by `activity:collapsed`: every day starts closed, so the sections
    /// below the first day can be looked at without scrolling.
    var startsCollapsed = false

    func isExpanded(_ day: ActivityDay, now: Date = Date()) -> Bool {
        if let chosen = expansion[day.id] { return chosen }
        if startsCollapsed { return false }
        guard let date = day.day else { return false }
        return now.timeIntervalSince(date) < 7 * 24 * 3600
    }

    /// Closes every day, whatever was chosen before.
    func collapseAll() {
        expansion.removeAll()
        startsCollapsed = true
    }

    func toggle(_ day: ActivityDay) {
        expansion[day.id] = !isExpanded(day)
    }
}

/// What a deep link asks Activity to show: carried as a one-shot request to the
/// Activity root (`Navigator.takeIntent`), so resolving a link changes nothing
/// and no second Activity screen is pushed; the screen applies it when it appears.
struct ActivityLink: Hashable, Codable {
    var scope: ActivityScope
    var query: String
    var collapsed: Bool

    /// The link as the opaque payload a `SectionIntent` carries.
    var payload: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init(scope: ActivityScope = .all, query: String = "", collapsed: Bool = false) {
        self.scope = scope
        self.query = query
        self.collapsed = collapsed
    }

    init?(payload: String) {
        guard let link = try? JSONDecoder().decode(ActivityLink.self, from: Data(payload.utf8)) else { return nil }
        self = link
    }

    /// Sets what the person sees to what the link asked for.
    @MainActor func apply(to filter: ActivityFilter) {
        filter.scope = scope
        filter.query = query
        if collapsed { filter.collapseAll() }
    }
}

/// Which rows the scope control shows.
enum ActivityScope: String, CaseIterable, Identifiable, Codable {
    case all, running, needsReview, failed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: Names.Scope.all
        case .running: Names.Scope.running
        case .needsReview: Names.Scope.needsReview
        case .failed: Names.Scope.failed
        }
    }

    var symbol: String {
        switch self {
        case .all: "list.bullet"
        case .running: "play.circle"
        case .needsReview: "eye"
        case .failed: "exclamationmark.triangle"
        }
    }

    func includes(_ row: ActivityRow) -> Bool {
        switch self {
        case .all: true
        case .running: row.isRunning
        case .needsReview: row.needsReview
        case .failed: row.isFailed
        }
    }
}
