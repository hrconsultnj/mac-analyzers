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

    enum Tab: String, CaseIterable {
        case memory = "Memory", monitor = "Monitor", storage = "Storage"
    }

    /// `tab` names the tab to open on (a snapshot host uses it); nil opens Memory.
    public init(tab: String? = nil) {
        _tab = State(initialValue: tab.flatMap { Tab(rawValue: $0) } ?? .memory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuJobsStrip()
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

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
