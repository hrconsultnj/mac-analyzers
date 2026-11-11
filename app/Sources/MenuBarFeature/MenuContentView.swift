import SwiftUI
import AnalyzersKit
import UIComponents

/// The MenuBarExtra(.window) dropdown: Memory | Storage tabs, live system
/// facts, two-line human-readable events, controls, shared footer.
///
/// This file is the dropdown's state and its tab switch. One tab per file:
///   MenuMemoryTab.swift    headline, live strip, recent guard events
///   MenuMonitorTab.swift   the biggest processes right now
///   MenuStorageTab.swift   disk usage and the storage cleanups
///   MenuFooter.swift       the footer every tab shares, and shared helpers
///   MenuJobsStrip.swift    the running job, above the tabs, only while there is one
public struct MenuContentView: View {
    @Environment(GuardLogStore.self) var store
    @Environment(JobStore.self) var jobs
    @Environment(UpdateState.self) var updates
    @Environment(\.openWindow) var openWindow
    @State private var tab: Tab = .memory
    @AppStorage("monitorRefreshSeconds") var monitorRefresh = 15
    @State var pauseError: String?
    @State var runNowPlans: [String: RunNowPlan] = [:]

    enum Tab: String, CaseIterable {
        case memory = "Memory", monitor = "Monitor", storage = "Storage"
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuJobsStrip()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .memory: memoryTab
            case .monitor: monitorTab
            case .storage: storageTab
            }

            Divider()
            footer
        }
        .padding(12)
        .onAppear {
            store.reload()
            loadRunNowPlans()
        }
    }
}
