import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory Guard: what it does when memory runs out, what it does about each kind of thing in Apps, Tools and macOS, and
/// the history of what it did. The same tabs as Monitor, one control for the whole screen.
///
///   GuardPlanTab.swift        When Memory Runs Out: the plan in a sentence, its steps, what is protected right now
///   GuardCategoryTab.swift    Apps, Tools and macOS: a group per kind, a row per rule, one table for the three
///   GuardRuleInspector.swift  the selected rule or kind, in words
///   GuardHistoryView.swift    History: what the guard did, a day at a time
///   GuardRulesModel.swift     the rules, what they match now, the would-have rows, the person's changes
///
/// In this version the rules engine only watches: it writes what each rule would have done and stops nothing. The guard
/// script does what it always did, for developer tooling.
struct GuardView: View {

    enum Tab: String, CaseIterable, Hashable, Sendable {
        case plan, apps, tools, macos, history
        var category: CensusGroup.Category? {
            switch self {
            case .apps: .apps
            case .tools: .tools
            case .macos: .system
            default: nil
            }
        }
    }

    @Environment(Navigator.self) private var navigator
    @State private var tab: Tab = .plan
    @State private var model = GuardRulesModel()
    /// Remembered: the panel at the right of the three tables.
    @AppStorage("guard.inspectorShown") private var inspectorShown = true

    private var tabItems: [ScopeTabItem<Tab>] {
        Tab.allCases.map { tab in
            switch tab {
            case .plan: ScopeTabItem(value: tab, title: Names.Guard.tabPlan, symbol: "exclamationmark.triangle", count: nil)
            case .history: ScopeTabItem(value: tab, title: Names.Guard.tabHistory, symbol: "clock.arrow.circlepath", count: nil)
            default:
                ScopeTabItem(value: tab, title: tab.category?.shortTitle ?? "", symbol: tab.category?.symbol ?? "square",
                             count: tab.category.map { model.weekCount($0) }.flatMap { $0 > 0 ? $0 : nil })
            }
        }
    }

    /// The tabs sit directly inside whatever the tab shows. A tab with a table also has the inspector, OUTSIDE the tabs: a bar
    /// outside the inspector would span the inspector too and cover its top. Each tab is its own view, so the inspector is
    /// there from the first frame (a panel that is switched on after the layout is not drawn).
    var body: some View {
        Group {
            switch tab {
            case .plan:
                bar(GuardPlanTab(model: model))
            case .apps, .tools, .macos:
                bar(GuardCategoryTab(model: model, category: tab.category ?? .apps))
                    .inspector(isPresented: $inspectorShown) {
                        GuardRuleInspector(model: model, selected: model.selection.first.flatMap { GuardCategoryTab.row(id: $0, model) })
                            .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
                    }
                    .toolbar { ToolbarItem { Toggle(isOn: $inspectorShown) { Label(Names.Monitor.inspector, systemImage: "sidebar.trailing") } } }
            case .history:
                bar(GuardHistoryView())
            }
        }
        .task { await model.refresh() }
        // a link that asks for the history (a search, a period, a kind of event) lands on its tab; the tab takes the request
        .onChange(of: navigator.pendingIntent) { showLinkedTab() }
        .task { showLinkedTab() }
    }

    private func bar<Content: View>(_ content: Content) -> some View {
        content.scopeTabsToolbar(screen: "guard", items: tabItems, selection: $tab)
    }

    private func showLinkedTab() {
        guard let payload = navigator.pendingIntent, payload.section == MemoryGroup.memoryGuard,
              let link = GuardLink(payload: payload.payload) else { return }
        if let name = link.tabName, let wanted = Tab(rawValue: name) { tab = wanted }
        else if link.scope != nil || link.query != nil || link.window != nil { tab = .history }
    }
}
