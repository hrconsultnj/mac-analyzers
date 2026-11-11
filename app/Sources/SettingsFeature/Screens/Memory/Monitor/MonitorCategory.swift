import AnalyzersKit
import Foundation

/// One tab of Monitor, in the shape the shared tabs control takes: a name, an
/// SF Symbol, and how much is in it. Today Monitor draws them as the search
/// field's scopes (text only, no counts); `categories(of:)` is what the shared
/// control will be handed, so moving over is one call.
struct MonitorCategory: Identifiable, Hashable {
    /// nil is the "Everything" tab.
    let category: CensusGroup.Category?
    let title: String
    let symbol: String
    let groups: Int
    let processes: Int
    let bytes: Int64

    var id: String { category?.rawValue ?? "everything" }
    var totalText: String { MemorySize.text(bytes) }

    static func categories(of rows: [MonitorRow]) -> [MonitorCategory] {
        let totals = MonitorTree.categoryTotals(rows)
        let everything = MonitorCategory(category: nil, title: "Everything", symbol: "square.stack.3d.up",
                                         groups: rows.count, processes: totals.reduce(0) { $0 + $1.processes },
                                         bytes: totals.reduce(Int64(0)) { $0 + $1.bytes })
        return [everything] + totals.map { total in
            MonitorCategory(category: total.category, title: total.category.shortTitle,
                            symbol: total.category.symbol, groups: total.groups,
                            processes: total.processes, bytes: total.bytes)
        }
    }
}

extension CensusGroup.Category {
    /// The tab's name: short, where the screen's own name for the category is long.
    var shortTitle: String {
        switch self {
        case .apps: "Apps"
        case .tools: "Tools"
        case .system: "macOS"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "app.fill"
        case .tools: "terminal.fill"
        case .system: "gearshape.fill"
        }
    }
}
