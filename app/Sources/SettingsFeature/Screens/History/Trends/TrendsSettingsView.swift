import SwiftUI
import Charts
import AnalyzersKit
import UIComponents

/// Trends: what the guard and the cleaners have done for this Mac, from its own
/// logs. A dashboard: the headline, what was defended and recovered as tiles
/// that open their detail as a table, the events per day, and the repeat
/// offenders. The period is a native menu in the toolbar; nothing leaves the Mac.
///
/// This file is the screen's state and its composition. One job next to it:
///   TrendsSettingsView+Sections.swift   the tiles, the chart and the offenders
///   TrendsEventTable.swift              the table every event drill-down shares
struct TrendsSettingsView: View {

    @Environment(Navigator.self) var navigator
    @State var period: TrendsModel.Period = .day30
    @State var snapshot: TrendsSnapshot?
    /// The tab shown; the shared tabs remember it across launches and
    /// `trends:memory` / `trends:storage` choose it.
    @State var category: TrendCategory = .memory
    /// Storage tab, level 3: what was deleted, by project.
    @State var projects: [DiskReclaimedGroup] = []

    private var tabItems: [ScopeTabItem<TrendCategory>] {
        TrendCategory.allCases.map {
            ScopeTabItem(value: $0, title: $0.title, symbol: $0.symbol, count: count($0))
        }
    }

    var body: some View {
        DataScreen(title: Names.Screen.trends, subtitle: period.headlinePrefix) {
            // a new list per tab, and once the logs have been read: the system list keeps the height it
            // measured for a row position, so the one-line "Reading the logs…" row would otherwise
            // leave the tiles and the chart that replace it a few points tall
            list.id("\(category.rawValue)-\(snapshot != nil)")
        }
            .scopeTabsToolbar(screen: "trends", items: tabItems, selection: $category)
            .toolbar {
                // A menu `Picker` in the toolbar draws an empty capsule (it does not show the
                // selected title there); a `Menu` shows its icon, and the period is in the subtitle.
                ToolbarItem {
                    Menu {
                        Picker("Period", selection: $period) {
                            ForEach(TrendsModel.Period.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(period.label, systemImage: "calendar")
                    }
                }
            }
            .task {
                if let payload = navigator.takeIntent(for: HistoryGroup.trends),
                   let requested = TrendCategory(rawValue: payload) { category = requested }
                await load()
            }
            .onChange(of: period) { Task { await load() } }
    }

    @ViewBuilder private var list: some View {
        if let snap = snapshot {
            List {
                Section {
                    Text(snap.headline)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if snap.isEmpty {
                    Section {
                        Text("No activity in this period yet. Trends fill in as the guard and cleanups run.")
                            .foregroundStyle(.secondary)
                    }
                } else if category == .memory {
                    memorySections(snap)
                } else {
                    storageSections(snap)
                }
            }
        } else {
            // not inside the list: a section's spinner sat at the top left; the state fills what the tabs leave
            LoadingState("Reading the logs…")
        }
    }

    /// How much each tab holds: guard events in Memory, cleanups that freed space in Storage.
    private func count(_ kind: TrendCategory) -> Int? {
        guard let snapshot else { return nil }
        return kind == .memory ? snapshot.kills + snapshot.spikes + snapshot.pressure + snapshot.cpuHogs
                               : snapshot.cleanRuns
    }

    private func load() async {
        let window = period
        await awaitLoad({ TrendsModel.snapshot(period: window) }) { snapshot = $0 }
        await awaitLoad({ TrendsModel.diskReclaimedByProject(period: window) }) { projects = $0 }
    }
}
