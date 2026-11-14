import SwiftUI
import AnalyzersKit

/// What can be pushed in the History group.
enum HistoryRoute: Hashable, Codable, Sendable {
    case trends(TrendsRoute)
}

/// Trends (and its drill-downs) and Undo.
@MainActor
enum HistoryGroup {

    static let trends = SectionID("trends")
    static let undo = SectionID("undo")

    static let group = SidebarGroup(
        title: Names.Group.history,
        rows: [
            SidebarRow(trends, Names.Screen.trends, symbol: "chart.xyaxis.line"),
            SidebarRow(undo, Names.Screen.undo, symbol: "arrow.uturn.backward"),
        ],
        root: screen,
        aliases: [
            "trends": .main(Location(trends)),
            "undo": .main(Location(undo)),
            "undo:trashed": undoIntent("trashed"),
            "undo:servers": undoIntent("servers"),
            "undo:opened": undoIntent("opened"),
            // the drill-downs, for 30 days (also what the snapshot renders open)
            "trends:kills": drill(.kills(.month)),
            "trends:spikes": drill(.spikes(.month)),
            "trends:pressure": drill(.pressure(.month)),
            "trends:cpu": drill(.cpuHogs(.month)),
            "trends:memory-freed": drill(.memoryFreed(.month)),
            // the two tabs: the screen opens on the one named
            "trends:memory": tab(.memory),
            "trends:storage": tab(.storage),
            "trends:disk": drill(.diskReclaimed(.month)),
            "trends:reclaimable": drill(.reclaimableNow),
        ],
        resolveDynamic: { target in
            // `trends:memory:24h`, `trends:storage:7d`: a tab with the period it should show
            for category in TrendCategory.allCases where target.hasPrefix("trends:\(category.rawValue):") {
                let name = String(target.dropFirst("trends:\(category.rawValue):".count))
                if let period = ReportPeriod(linkName: name) {
                    return .mainWithIntent(Location(trends), SectionIntent(section: trends, payload: "\(category.rawValue)|\(period.rawValue)"))
                }
            }
            // `trends:offender:<name>` — that process's timeline over 30 days
            guard target.hasPrefix("trends:offender:") else { return nil }
            return drill(.offender(String(target.dropFirst("trends:offender:".count)), .month))
        })

    private static func undoIntent(_ payload: String) -> Resolution {
        .mainWithIntent(Location(undo), SectionIntent(section: undo, payload: payload))
    }

    private static func tab(_ category: TrendCategory) -> Resolution {
        .mainWithIntent(Location(trends), SectionIntent(section: trends, payload: category.rawValue))
    }

    private static func drill(_ route: TrendsRoute) -> Resolution {
        .main(Location(trends, path: [.history(.trends(route))]))
    }

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case trends: TrendsSettingsView()
        case undo: UndoView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: HistoryRoute) -> some View {
        switch route {
        case .trends(let route): trendsDestination(route)
        }
    }
}
