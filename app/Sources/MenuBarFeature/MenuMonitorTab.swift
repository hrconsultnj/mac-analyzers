import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The Monitor tab: who is using memory, from the same census, names and footprint numbers as Monitor. A small
/// tab bar picks the category (All, Apps, Tools, macOS: the shared `ScopeTabs`); the groups are rows of the app's
/// one table for rows that open (`OutlineTable`), each opening to its parts (an app) or its separate programs (a
/// tool), with Quit, Stop or a lock in a column on the right. One file per job:
///   MenuMonitorTable.swift   the table and its cells
///   MenuPanelStopFlow.swift  the confirmation and notices under it
extension MenuContentView {

    @ViewBuilder var monitorTab: some View {
        HStack {
            pressureRow
            Spacer()
            Picker("Refresh", selection: $monitorRefresh) {
                Text("Every 5 Seconds").tag(5)
                Text("Every 15 Seconds").tag(15)
                Text("Every Minute").tag(60)
                Text("Never").tag(0)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("How often this list refreshes while open")
        }
        .task(id: monitorRefresh) { await refreshCensus() }

        if let panel {
            ScopeTabs(selection: $monitorScope, items: monitorScopeItems(panel))
                .controlSize(.small)
                .scopeTabMemory(key: "panel.monitor", selection: $monitorScope, items: monitorScopeItems(panel))
            let shown = panel.nodes(in: monitorScope.category)
            MenuMonitorTable(nodes: shown.nodes, scope: monitorScope, flow: stopFlow,
                             reload: { Task { await refreshCensus(once: true) } })
            MenuStopPrompt(flow: stopFlow, reload: { Task { await refreshCensus(once: true) } })
            if shown.more > 0 {
                MenuRowButton(action: { SettingsOpener.open(target: monitorScope.category?.monitorLink ?? "monitor") }) {
                    HStack {
                        Text("\(shown.more) more in \(Names.Screen.monitor)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)  // decorative disclosure arrow
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading every process…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The tabs with the number of groups in each; a category with none is not drawn.
    private func monitorScopeItems(_ panel: MenuPanelModel) -> [ScopeTabItem<MonitorScope>] {
        MonitorScope.allCases.compactMap { scope in
            let count = panel.groupCount(in: scope.category)
            return scope == .all || count > 0
                ? ScopeTabItem(value: scope, title: scope.title, symbol: scope.symbol, count: count == 0 ? nil : count) : nil
        }
    }

    /// One census, off the main actor, then again every `monitorRefresh`
    /// seconds while this tab stays open (the task is cancelled when it does not).
    func refreshCensus(once: Bool = false) async {
        repeat {
            let taken = await Task.detached(priority: .userInitiated) {
                MenuPanelModel(census: MemoryCensus.take())
            }.value
            panel = taken
            guard !once, monitorRefresh > 0 else { return }
            try? await Task.sleep(for: .seconds(Double(monitorRefresh)))
        } while !Task.isCancelled && !once
    }
}
