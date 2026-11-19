import SwiftUI
import AnalyzersKit
import UIComponents

/// How It Works: an explainer in four tabs (Memory, Storage, System, Your Data). Each tab is a list of topics, a row with
/// one sentence that has this Mac's number in it; a row opens the topic's own screen. The topics also open from the help
/// button of the screen they explain (`helpTopic`).
struct HowItWorksView: View {
    @Environment(Navigator.self) private var navigator
    @State private var tab = HowItWorksTab.memory
    private var model: HowItWorksModel { .shared }

    private var tabItems: [ScopeTabItem<HowItWorksTab>] {
        HowItWorksTab.allCases.map { tab in
            ScopeTabItem(value: tab, title: tab.title, symbol: tab.symbol,
                         count: HowItWorksTopic.allCases.filter { $0.tab == tab }.count)
        }
    }

    var body: some View {
        DataScreen(title: Names.Screen.howItWorks, subtitle: "How Sparehold decides, measures and writes everything down") {
            if let facts = model.facts {
                List {
                    ForEach(HowItWorksTopic.allCases.filter { $0.tab == tab }) { topic in
                        row(topic, facts: facts)
                    }
                    if tab == .yourData {
                        moved
                        #if canImport(ProKit)
                        ProAboutSlot()
                        #endif
                    }
                }
                .listStyle(.inset)
                .runHistoryRows()
            } else {
                LoadingState("Reading this Mac…")
            }
        }
        .scopeTabsToolbar(screen: "howItWorks", items: tabItems, selection: $tab, isActive: navigator.path.isEmpty)
        .task { await model.load() }
    }

    /// A topic row: its symbol, its title and the sentence with this Mac's number, then a chevron.
    private func row(_ topic: HowItWorksTopic, facts: HowItWorksFacts) -> some View {
        Button { navigator.push(.app(.topic(topic))) } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                        Text(topic.title).font(Tokens.Typography.rowTitleKey)
                        Text(topic.content(facts).summary)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    // an icon tile: its size is its job, so the titles of rows with different symbols line up
                    Image(systemName: topic.symbol).frame(width: Tokens.Icon.row, height: Tokens.Icon.row)
                }
                .labelStyle(.centeredIcon)
                Spacer(minLength: Tokens.Space.xl)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Where Turn Off used to be in this screen: it is in Setup now, with the rest of this Mac's configuration.
    private var moved: some View {
        Section {
            Button { navigator.open(target: "uninstall") } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                            Text(Names.HowItWorks.turnOffMoved).font(Tokens.Typography.rowTitleKey)
                            Text("Pause it, switch off background protection, or remove it from this Mac, with proof that it worked. It is in Setup now.")
                                .font(Tokens.Typography.body)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "power").frame(width: Tokens.Icon.row, height: Tokens.Icon.row)
                    }
                    .labelStyle(.centeredIcon)
                    Spacer(minLength: Tokens.Space.xl)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
