import Foundation
import AnalyzersKit

/// What a deep link asks Memory Guard to show: a tab, a search, a period.
/// `log:forensics` opens the Crisis Reports tab; `log:guardLog` opens All.
/// Carried as the one-shot request a `SectionIntent` holds.
struct GuardLink: Codable {
    var scopeName: String?
    var query: String?
    var windowHours: Int?

    var scope: GuardHistory.Scope? { scopeName.flatMap { GuardHistory.Scope(rawValue: $0) } }
    var window: GuardHistoryModel.Window? { windowHours.flatMap { GuardHistoryModel.Window(rawValue: $0) } }

    init(scope: GuardHistory.Scope? = nil, query: String? = nil, window: GuardHistoryModel.Window? = nil) {
        scopeName = scope?.rawValue
        self.query = query
        windowHours = window?.rawValue
    }

    init?(payload: String) {
        guard let link = try? JSONDecoder().decode(GuardLink.self, from: Data(payload.utf8)) else { return nil }
        self = link
    }

    var payload: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The link a `guard:…` target means: a tab (`stopped`, `alerts`, `reports`, `all`) or `find:<text>`.
    static func parse(_ rest: String) -> GuardLink? {
        let scopes: [String: GuardHistory.Scope] = ["all": .all, "stopped": .stopped, "alerts": .alerts,
                                                    "reports": .crisisReports]
        if let scope = scopes[rest] { return GuardLink(scope: scope) }
        if rest.hasPrefix("find:") { return GuardLink(query: String(rest.dropFirst(5))) }
        return nil
    }
}
