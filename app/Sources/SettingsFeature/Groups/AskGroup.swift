import SwiftUI
import AnalyzersKit

/// Ask: the agent's home, the one feature row at the top of the sidebar. Pro
/// only — a free build has no row and no section (`#if canImport(ProKit)`, the
/// same seam as Support). The row's own screens (the live session, the
/// receipt) are pushed as `Route.ask` payloads once the session layer lands
/// (Phase 4); the section root is the home screen.
@MainActor
enum AskGroup {

    static let ask = SectionID("ask")

    static let group = SidebarGroup(
        title: nil,
        rows: rows,
        root: screen,
        aliases: [
            "ask": .main(Location(ask)),
        ])

    /// Pro builds get the row; free builds get nothing — not a greyed row.
    private static var rows: [SidebarRow] {
        var rows: [SidebarRow] = []
        #if canImport(ProKit)
        rows.append(SidebarRow(ask, Names.Screen.ask, symbol: "text.bubble", tint: .mint))
        #endif
        return rows
    }

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case ask: AskHomeView()
        default: EmptyView()
        }
    }
}
