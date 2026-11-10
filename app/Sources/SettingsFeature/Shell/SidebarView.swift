import SwiftUI
import AnalyzersKit
#if canImport(ProKit)
import ProKit
#endif

/// The sidebar: a list of plain labels grouped by the registry, selection
/// bound to the navigator. Picking a row calls `select`; picking the row that
/// is already selected does nothing.
struct SidebarView: View {
    let navigator: Navigator

    @State private var updateAvailable = false
    @State private var setupNeedsAttention = false

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
        #if canImport(ProKit)
        .safeAreaInset(edge: .bottom) { ProBadgeSlot() }
        #endif
        .task {
            if let latest = await UpdateChecker.latestVersion() {
                updateAvailable = UpdateChecker.isNewer(latest, than: UpdateChecker.installedVersion)
            }
        }
        .task {
            // cheap version of the checklist: is anything actually broken?
            let engine = await Task.detached(priority: .utility) { EngineStatus.probe() }.value
            setupNeedsAttention = !engine.isFullyInstalled
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
                .badge(badge(row.badge))
                .tag(row.section)
        }
    }

    // The Setup row STAYS after everything is green — permissions get
    // withdrawn and background jobs get unloaded without asking. Only the
    // badge goes away.
    private func badge(_ badge: SidebarBadge?) -> Text? {
        switch badge {
        case .needsAttention: setupNeedsAttention ? Text("!") : nil
        case .updateAvailable: updateAvailable ? Text("1") : nil
        case nil: nil
        }
    }
}
