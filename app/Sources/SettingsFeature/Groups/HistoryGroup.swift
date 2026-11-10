import SwiftUI

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
        title: "History",
        rows: [
            SidebarRow(trends, "Trends", symbol: "chart.xyaxis.line"),
            SidebarRow(undo, "Undo", symbol: "arrow.uturn.backward"),
        ],
        root: screen,
        resolve: resolve)

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

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "trends": Location(trends)
        case "undo": Location(undo)
        default: nil
        }
    }
}
