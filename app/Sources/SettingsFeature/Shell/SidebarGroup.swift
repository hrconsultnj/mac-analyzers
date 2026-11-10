import SwiftUI

/// A badge a sidebar row can carry. The sidebar owns the state behind each
/// one (it is shell-level information); a group only says which row wears it.
enum SidebarBadge: Hashable {
    /// Something on this Mac is not working (Setup).
    case needsAttention
    /// A newer release exists (Updates).
    case updateAvailable
}

/// One sidebar row: plain label, SF Symbol, optional badge.
struct SidebarRow: Identifiable, Hashable {
    let section: SectionID
    let title: String
    let symbol: String
    var badge: SidebarBadge?

    var id: SectionID { section }

    init(_ section: SectionID, _ title: String, symbol: String, badge: SidebarBadge? = nil) {
        self.section = section
        self.title = title
        self.symbol = symbol
        self.badge = badge
    }
}

/// Everything one sidebar group contributes, declared in that group's own
/// file: its rows, the screen behind each section, and the deep-link targets
/// that land inside it. The shell only knows the order of the groups
/// (`SectionRegistry`), so adding or changing a screen never edits shared code.
@MainActor
struct SidebarGroup {
    /// Header text; nil renders the rows with no header.
    let title: String?
    let rows: [SidebarRow]
    /// Every section this group owns, including ones with no row.
    let sections: Set<SectionID>
    /// The screen at the root of a section this group owns.
    let root: @MainActor (SectionID) -> AnyView
    /// Deep-link aliases this group answers. Returns nil for a target that is
    /// not this group's.
    let resolve: @MainActor (String) -> Location?

    init<Root: View>(title: String?,
                     rows: [SidebarRow],
                     hidden: [SectionID] = [],
                     @ViewBuilder root: @escaping @MainActor (SectionID) -> Root,
                     resolve: @escaping @MainActor (String) -> Location?) {
        self.title = title
        self.rows = rows
        self.sections = Set(rows.map(\.section) + hidden)
        self.root = { AnyView(root($0)) }
        self.resolve = resolve
    }
}
