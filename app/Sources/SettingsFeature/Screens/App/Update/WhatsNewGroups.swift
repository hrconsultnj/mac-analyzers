import SwiftUI
import AnalyzersKit

/// One section of the What's New list: the screen a set of features belongs to.
struct WhatsNewGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let items: [WhatsNewItem]
}

/// Features grouped by the screen they belong to, in the sidebar's own order, so What's New reads like the
/// sidebar: Overview, Memory, Storage, System, History, Settings, then the app. After the screens come the
/// changes across the app, then, for releases written before tags existed, the bold topic each bullet sat under,
/// and last everything else. Only this module knows a screen's title and icon, so grouping lives here and not in
/// the kernel.
@MainActor
enum WhatsNewGroups {

    static func build(items: [WhatsNewItem]) -> [WhatsNewGroup] {
        var screens: [SectionID: (order: Int, title: String, symbol: String, items: [WhatsNewItem])] = [:]
        var throughout: [WhatsNewItem] = []
        var topics: [String: [WhatsNewItem]] = [:]
        var topicOrder: [String] = []
        var earlier: [WhatsNewItem] = []

        let rows = sidebarRows()
        for item in items {
            switch item.scope {
            case .app:
                throughout.append(item)
            case .screen(let target):
                if let section = section(of: target), let row = rows[section] {
                    screens[section, default: (row.order, row.title, row.symbol, [])].items.append(item)
                } else {
                    // a target the app does not know (a screen that was renamed since): the change is still news
                    throughout.append(item)
                }
            case .untagged:
                if let topic = item.topic {
                    if topics[topic] == nil { topicOrder.append(topic) }
                    topics[topic, default: []].append(item)
                } else {
                    earlier.append(item)
                }
            }
        }

        var groups = screens.sorted { $0.value.order < $1.value.order }
            .map { WhatsNewGroup(id: "screen:\($0.key.rawValue)", title: $0.value.title, symbol: $0.value.symbol, items: $0.value.items) }
        if !throughout.isEmpty {
            groups.append(WhatsNewGroup(id: "app", title: Names.WhatsNew.throughoutTheApp, symbol: "macwindow", items: throughout))
        }
        groups += topicOrder.map { WhatsNewGroup(id: "topic:\($0)", title: $0, symbol: "sparkles", items: topics[$0] ?? []) }
        if !earlier.isEmpty {
            groups.append(WhatsNewGroup(id: "earlier", title: Names.WhatsNew.earlierChanges, symbol: "clock.arrow.circlepath", items: earlier))
        }
        return groups
    }

    /// The sidebar section a deep-link target lands in; nil when the target is not one the app answers.
    static func section(of target: String) -> SectionID? {
        switch DeepLinkRouter.resolve(target) {
        case .main(let location), .mainWithIntent(let location, _): location.section
        case .preferences(let tab): SettingsGroup.interimLocation(forTab: tab).section
        case .welcome, .unknown: nil   // the Welcome flow is a window of its own, no sidebar row
        }
    }

    /// The screen's name and icon as the sidebar shows them, and its place in the sidebar's order.
    static func screen(of target: String) -> (title: String, symbol: String)? {
        guard let section = section(of: target), let row = sidebarRows()[section] else { return nil }
        return (row.title, row.symbol)
    }

    private static func sidebarRows() -> [SectionID: (order: Int, title: String, symbol: String)] {
        var rows: [SectionID: (Int, String, String)] = [:]
        var order = 0
        for group in SectionRegistry.groups {
            for row in group.rows {
                rows[row.section] = (order, row.title, row.symbol)
                order += 1
            }
        }
        return rows
    }
}
