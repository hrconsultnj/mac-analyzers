import SwiftUI
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

    var body: some View {
        List(selection: selection) {
            ForEach(Array(SectionRegistry.groups.enumerated()), id: \.offset) { _, group in
                if let title = group.title {
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
        ForEach(group.rows) { row in
            Label(row.title, systemImage: row.symbol)
                .badge(row.badge?().map { Text($0) })
                .tag(row.section)
        }
    }
}
