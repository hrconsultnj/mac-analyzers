import SwiftUI
import UIComponents
#if canImport(ProKit)
import ProKit
#endif

/// The sidebar: a list of plain labels grouped by the registry, selection
/// bound to the navigator. Picking a row calls `select`; picking the row that
/// is already selected does nothing. Badges and the work behind them belong to
/// the groups; this view only draws what they say.
struct SidebarView: View {
    let navigator: Navigator
    /// Shown as the hover overlay: one sheet of glass, so the footer has no bar behind it.
    var floating = false
    @AppStorage(SidebarIconStyle.key) private var iconStyle = SidebarIconStyle.coloured

    var body: some View {
        List(selection: selection) {
            ForEach(Array(SectionRegistry.groups.enumerated()), id: \.offset) { _, group in
                if group.rows.contains(where: \.inSidebar) == false {
                    EmptyView()
                } else if let title = group.title {
                    Section(title) { rows(group) }
                } else {
                    Section { rows(group) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                #if canImport(ProKit)
                ProBadgeSlot()
                #endif
                Divider()
                SidebarWhatsNewCard(navigator: navigator, floating: floating)
                SidebarVersionItem(navigator: navigator, floating: floating)
            }
        }
        .task {
            // each group feeds its own badges; one slow probe never holds up another
            await withTaskGroup(of: Void.self) { tasks in
                for group in SectionRegistry.groups where group.load != nil {
                    tasks.addTask { await group.load?() }
                }
            }
        }
    }

    private var selection: Binding<SectionID?> {
        Binding(get: { navigator.section },
                set: { if let section = $0 { navigator.select(section) } })
    }

    @ViewBuilder
    private func rows(_ group: SidebarGroup) -> some View {
        ForEach(group.rows.filter(\.inSidebar)) { row in
            // The system draws no colour for a sidebar glyph in this app (`.listItemTint` with `.preferred` or `.fixed`
            // renders grey, checked off-screen on macOS 27), so the coloured style is the shared tile; Plain is the symbol.
            Group {
                if iconStyle == .coloured {
                    Label {
                        Text(row.title)
                    } icon: {
                        IconTile(symbol: row.symbol, color: row.tint, side: Tokens.Icon.row)
                    }
                } else {
                    Label(row.title, systemImage: row.symbol)
                }
            }
                .badge(row.badge?().map { Text($0) })
                .tag(row.section)
        }
    }
}
