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
    /// Remembered between launches; the last 30 days to begin with.
    @State var period = ReportPeriod.saved(key: Self.periodKey, fallback: .month)
    static let periodKey = "trends.periodHours"
    /// The period whose numbers are being read; the previous ones stay on screen until they arrive.
    @State var loadingPeriod: ReportPeriod?
    /// Which load is the newest (see `load`).
    @State var loadGeneration = 0
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
        DataScreen(title: Names.Screen.trends, subtitle: periodSubtitle(loading: loadingPeriod, period.title)) {
            // a new list per tab, and once the logs have been read: the system list keeps the height it
            // measured for a row position, so the one-line "Reading the logs…" row would otherwise
            // leave the tiles and the chart that replace it a few points tall
            list.id("\(category.rawValue)-\(snapshot != nil)")
        }
            .scopeTabsToolbar(screen: "trends", items: tabItems, selection: $category)
            .toolbar { PeriodToolbar(period: $period, loading: loadingPeriod) }
            .task(id: period) {
                applyPendingLink()
                period.remember(key: Self.periodKey)
                await load()
            }
            // a link opened while Trends is already showing
            .onChange(of: navigator.pendingIntent) { applyPendingLink() }
    }

    /// A deep link's tab, and its period when it names one (`memory` or `memory|168`).
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: HistoryGroup.trends) else { return }
        let parts = payload.split(separator: "|").map(String.init)
        if let name = parts.first, let requested = TrendCategory(rawValue: name) { category = requested }
        if parts.count > 1, let hours = Int(parts[1]), let requested = ReportPeriod(rawValue: hours) { period = requested }
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
        loadGeneration += 1
        let mine = loadGeneration
        loadingPeriod = window
        // The snapshot and the project rows are read together and assigned together, so the rows are never of another
        // period than the numbers beside them. A result is kept only if its load is still the newest and its period the
        // one chosen: a load that was superseded can finish after the one that replaced it. Keyed by the period too: the
        // coordinator serves a key for a few seconds, and one key for every period answered a period chosen right after
        // another with the first one's numbers.
        await awaitLoad({ (TrendsModel.snapshot(period: window), TrendsModel.diskReclaimedByProject(period: window)) },
                        key: "trends.\(window.rawValue)") { loaded in
            guard mine == loadGeneration, window == period else { return }
            snapshot = loaded.0
            projects = loaded.1
        }
        if !Task.isCancelled, mine == loadGeneration { loadingPeriod = nil }
    }
}
