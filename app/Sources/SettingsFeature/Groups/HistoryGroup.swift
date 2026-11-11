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
        ])

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
