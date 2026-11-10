import SwiftUI
import AnalyzersKit

/// What can be pushed in the System group.
enum SystemRoute: Hashable, Codable, Sendable {
    /// The persistence-change log (what was added to or removed from startup).
    case changes
}

/// Network, Login & Startup Items and Reports.
@MainActor
enum SystemGroup {

    static let network = SectionID("network")
    static let loginItems = SectionID("loginItems")
    static let reports = SectionID("reports")

    static let group = SidebarGroup(
        title: "System",
        rows: [
            SidebarRow(network, "Network", symbol: "network"),
            SidebarRow(loginItems, "Login & Startup Items", symbol: "person.crop.circle.badge.questionmark"),
            SidebarRow(reports, "Reports", symbol: "doc.text.magnifyingglass"),
        ],
        root: screen,
        aliases: [
            "network": .main(Location(network)),
            "reports": .main(Location(reports)),
            "loginitems": .main(Location(loginItems)),
            "log:loginItems": .main(Location(loginItems)),
            "log:persistence": .main(Location(loginItems, path: [.system(.changes)])),
        ])

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case network: NetworkSettingsView()
        case loginItems: LoginItemsRoot()
        case reports: ReportsSettingsView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: SystemRoute) -> some View {
        switch route {
        case .changes: LogsSettingsView(kind: .persistence)
        }
    }
}

private struct LoginItemsRoot: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        LoginItemsView()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Changes") { navigator.push(.system(.changes)) }
                        .help("What was added to or removed from startup")
                }
            }
    }
}
