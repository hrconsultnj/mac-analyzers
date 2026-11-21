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

/// The conversations the Ask screens share. The box holds every LIVE session
/// by its conversation id — one slot made navigating to another chat drop the
/// first one's streaming turn, which is component state, not app state. The
/// home reopens a conversation through `session(for:)`: a live one continues
/// where it is, a saved one rehydrates from the history store. A restored
/// stack that lands on `.session` after a restart finds `current` nil, and
/// the session screen says so with its own empty state.
@MainActor @Observable
final class AskSessionBox {
    private var live: [UUID: AskSession] = [:]
    var current: AskSession? {
        didSet { if let session = current { live[session.id] = session } }
    }

    /// The live session for a conversation, when one is still running here.
    func session(for id: UUID) -> AskSession? { live[id] }
}

/// Ask: the agent's home, the one feature row at the top of the sidebar. The
/// sparkles mark says AI. EVERY build gets the row while the product is in
/// this phase — the free/paid line will come back when licensing lands (the
/// ProKit seam stays available for it; the row simply no longer reads it).
/// The row's screens (the live session, and the receipt it ends in) push as
/// `Route.ask` payloads.
@MainActor
enum AskGroup {

    static let ask = SectionID("ask")

    /// The one box the Ask screens read. Group-owned, like the badges' state.
    fileprivate static let conversation = AskSessionBox()

    static let group = SidebarGroup(
        title: nil,
        rows: [
            SidebarRow(ask, Names.Screen.ask, symbol: "sparkles", tint: .mint),
        ],
        root: screen,
        aliases: [
            "ask": .main(Location(ask)),
        ])

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
