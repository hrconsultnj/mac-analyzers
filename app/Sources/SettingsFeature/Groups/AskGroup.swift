import SwiftUI
import AgentFeature
import AnalyzersKit

/// What can be pushed in the Ask group. The receipt (S4) renders inside the
/// session screen today; its own case lands when Phase 5 wires the preview
/// round-trip to the reviewed screen.
enum AskRoute: Hashable, Codable, Sendable {
    /// The live conversation (S2).
    case session
}

/// The conversation the Ask screens share: the home starts one, the session
/// screen shows it. The group owns the box, the way a group owns its badge's
/// state — screens read it through the environment this file injects at both
/// places the Ask screens appear (the section root and the pushed route). A
/// restored stack that lands on `.session` after a restart finds `current`
/// nil, and the session screen says so with its own empty state.
@MainActor @Observable
final class AskSessionBox {
    var current: AskSession?
}

/// Ask: the agent's home, the one feature row at the top of the sidebar. Pro
/// only — a free build has no row and no section (`#if canImport(ProKit)`, the
/// same seam as Support). The row's screens (the live session, and the receipt
/// it ends in) push as `Route.ask` payloads.
@MainActor
enum AskGroup {

    static let ask = SectionID("ask")

    /// The one box the Ask screens read. Group-owned, like the badges' state.
    fileprivate static let conversation = AskSessionBox()

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
        case ask: AskHomeView().environment(conversation)
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: AskRoute) -> some View {
        switch route {
        case .session: AskSessionView().environment(conversation)
        }
    }
}
