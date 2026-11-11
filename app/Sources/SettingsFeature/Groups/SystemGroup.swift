import SwiftUI
import AnalyzersKit

/// What can be pushed in the System group.
enum SystemRoute: Hashable, Codable, Sendable {
    /// A report's raw Markdown, one level below the reader. Holds the file's
    /// path: a route is an identifier, never the text.
    case rawReport(path: String)
}

/// Network, Login & Startup Items and Reports.
@MainActor
enum SystemGroup {

    static let network = SectionID("network")
    static let loginItems = SectionID("loginItems")
    static let reports = SectionID("reports")

    static let group = SidebarGroup(
        title: Names.Group.system,
        rows: [
            SidebarRow(network, Names.Screen.network, symbol: "network"),
            SidebarRow(loginItems, Names.Screen.loginItems, symbol: "person.crop.circle.badge.questionmark"),
            SidebarRow(reports, Names.Screen.reports, symbol: "doc.text.magnifyingglass"),
        ],
        root: screen,
        aliases: [
            "network": .main(Location(network)),
            "reports": .main(Location(reports)),
            "loginitems": .main(Location(loginItems)),
            "log:loginItems": .main(Location(loginItems)),
            // the startup-changes history is the Changes scope of Login & Startup Items
            "log:persistence": .mainWithIntent(Location(loginItems),
                                               SectionIntent(section: loginItems, payload: "changes")),
        ],
        resolveDynamic: resolveDynamic)

    /// Targets that carry a request for the screen to apply when it appears:
    ///  - `startup:changes|leftovers|select:<name>` — Login & Startup Items on the Changes scope,
    ///    filtered to leftovers, or with that item open in the inspector;
    ///  - `network:history|older|pick:<n>` — Network on History, on the previous snapshot, or
    ///    with the nth-largest program open;
    ///  - `reports:pick:<n>|raw` — Reports with the nth report open, or its source pushed.
    /// Pure: the screen reads the data and applies the request when it has it.
    private static func resolveDynamic(_ target: String) -> Resolution? {
        let sections: [(prefix: String, section: SectionID)] = [
            ("startup:", loginItems), ("network:", network), ("reports:", reports),
        ]
        for (prefix, section) in sections where target.hasPrefix(prefix) {
            return .mainWithIntent(Location(section),
                                   SectionIntent(section: section, payload: String(target.dropFirst(prefix.count))))
        }
        return nil
    }

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case network: NetworkView()
        case loginItems: LoginItemsView()
        case reports: ReportsView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: SystemRoute) -> some View {
        switch route {
        case .rawReport(let path): ReportRawView(path: path)
        }
    }
}
