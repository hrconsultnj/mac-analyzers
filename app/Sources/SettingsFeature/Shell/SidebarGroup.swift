import SwiftUI

/// What a deep-link target means: a place in the main window, or a tab of the
/// Settings window (which does not exist yet — see `PreferencesGroup`).
enum Resolution: Equatable {
    case main(Location)
    case preferences(tab: String)
    case unknown
}

/// One sidebar row: plain label, SF Symbol, and an optional badge. The badge
/// is a closure the sidebar reads while drawing, so the state behind it lives
/// in the group's own file (an `@Observable` it owns), not in the shell.
struct SidebarRow: Identifiable {
    let section: SectionID
    let title: String
    let symbol: String
    var badge: (@MainActor () -> String?)?

    var id: SectionID { section }

    init(_ section: SectionID, _ title: String, symbol: String,
         badge: (@MainActor () -> String?)? = nil) {
        self.section = section
        self.title = title
        self.symbol = symbol
        self.badge = badge
    }
}

/// Everything one sidebar group contributes, declared in that group's own
/// file: its rows, the screen behind each section, its badges, and the
/// deep-link targets that land inside it. The shell only knows the order of
/// the groups (`SectionRegistry`), so adding or changing a screen never edits
/// shared code.
@MainActor
struct SidebarGroup {
    /// Header text; nil renders the rows with no header.
    let title: String?
    let rows: [SidebarRow]
    /// Every section this group owns, including ones with no row.
    let sections: Set<SectionID>
    /// The screen at the root of a section this group owns.
    let root: @MainActor (SectionID) -> AnyView
    /// Fixed deep-link targets this group answers. Each target may be claimed
    /// by one group only; the registry checks that in debug builds.
    let aliases: [String: Resolution]
    /// Targets that carry data (`job:<id>`). Asked only after every group's
    /// fixed aliases have had their say.
    let resolveDynamic: (@MainActor (String) -> Resolution?)?
    /// Work the sidebar starts when it appears (feeding a badge, say).
    let load: (@MainActor () async -> Void)?

    init<Root: View>(title: String?,
                     rows: [SidebarRow],
                     hidden: [SectionID] = [],
                     @ViewBuilder root: @escaping @MainActor (SectionID) -> Root,
                     aliases: [String: Resolution],
                     resolveDynamic: (@MainActor (String) -> Resolution?)? = nil,
                     load: (@MainActor () async -> Void)? = nil) {
        self.title = title
        self.rows = rows
        self.sections = Set(rows.map(\.section) + hidden)
        self.root = { AnyView(root($0)) }
        self.aliases = aliases
        self.resolveDynamic = resolveDynamic
        self.load = load
    }
}
