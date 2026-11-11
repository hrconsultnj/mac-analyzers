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
    /// The tab shown, remembered across launches; `trends:memory` / `trends:storage` choose it.
    @AppStorage("trends.category") private var categoryRaw = TrendCategory.memory.rawValue
    var category: TrendCategory {
        get { TrendCategory(rawValue: categoryRaw) ?? .memory }
        nonmutating set { categoryRaw = newValue.rawValue }
    }
    /// Storage tab, level 3: what was deleted, by project.
    @State var projects: [DiskReclaimedGroup] = []

    var body: some View {
        List {
            if let snap = snapshot {
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
            } else {
                Section { ProgressView("Reading the logs…") }
            }
        }
        .navigationTitle(Names.Screen.trends)
        .navigationSubtitle(period.headlinePrefix)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: Binding(get: { category }, set: { category = $0 })) {
                    ForEach(TrendCategory.allCases) { kind in
                        Label("\(kind.title)\(count(kind).map { " (\($0))" } ?? "")", systemImage: kind.symbol)
                            .labelStyle(.titleAndIcon)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
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
