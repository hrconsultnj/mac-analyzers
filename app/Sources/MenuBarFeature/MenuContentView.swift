import SwiftUI
import AnalyzersKit
import UIComponents

/// The MenuBarExtra(.window) panel: Memory | Monitor | Storage tabs over a
/// shared footer, with the running job above them while there is one.
///
/// Native controls at the system's small size, set once here (a panel is the
/// dense case the platform allows); no fixed widths and no forced single
/// lines, so a longer name wraps instead of truncating.
///
/// This file is the panel's state and its tab switch. One tab per file:
///   MenuMemoryTab.swift    the guard's state, recent events, the guard's actions
///   MenuMonitorTab.swift   who is using memory, from the same census as Monitor
///   MenuStorageTab.swift   disk, the scheduled cleans, and where to review them
///   MenuFooter.swift       the footer every tab shares, and shared helpers
///   MenuComponents.swift   the full-width row button and the event row
///   MenuJobsStrip.swift    the running job, only while there is one
public struct MenuContentView: View {
    @Environment(GuardLogStore.self) var store
    @Environment(JobStore.self) var jobs
    @Environment(UpdateState.self) var updates
    @Environment(\.openWindow) var openWindow
    @State private var tab: Tab
    @AppStorage("monitorRefreshSeconds") var monitorRefresh = 15
    @State var pauseError: String?
    @State var runNowPlans: [String: RunNowPlan] = [:]
    /// Monitor tab: the census, taken off the main actor while that tab is open.
    @State var panel: MenuPanelModel?
    /// The Monitor tab's category tab, and what a Quit or Stop on its rows is doing.
    @State var monitorScope: MonitorScope = .all
    @State var stopFlow = PanelStopFlow()
    /// A host (the snapshot tool) asked for a tab: then the remembered one is not restored.
    private let pinnedTab: Bool

    enum Tab: String, CaseIterable, Sendable {
        case memory = "Memory", monitor = "Monitor", storage = "Storage"

        var symbol: String {
            switch self {
            case .memory: "memorychip"
            case .monitor: "gauge.with.dots.needle.33percent"
            case .storage: "internaldrive"
            }
        }
    }

    /// Memory carries today's stops (the number its first line reports) while there are
    /// any; Monitor and Storage have no count that means anything.
    private var tabItems: [ScopeTabItem<Tab>] {
        Tab.allCases.map { kind in
            ScopeTabItem(value: kind, title: kind.rawValue, symbol: kind.symbol,
                         count: kind == .memory && store.killsToday > 0 ? store.killsToday : nil)
        }
    }

    /// `tab` names the tab to open on (a snapshot host uses it); nil opens Memory.
    public init(tab: String? = nil) {
        pinnedTab = tab != nil
        _tab = State(initialValue: tab.flatMap { Tab(rawValue: $0) } ?? .memory)
    }

    @ViewBuilder private var tabs: some View {
        if pinnedTab {
            ScopeTabs(selection: $tab, items: tabItems).controlSize(.small)
        } else {
            ScopeTabs(selection: $tab, items: tabItems).controlSize(.small)
                .scopeTabMemory(key: "panel", selection: $tab, items: tabItems)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuJobsStrip()
            tabs

            switch tab {
            case .memory: memoryTab
            case .monitor: monitorTab
            case .storage: storageTab
            }

            Divider()
            footer
        }
        .controlSize(.small)
        .padding(12)
        .onAppear {
            store.reload()
            loadRunNowPlans()
        }
    }
}
