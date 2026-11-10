import SwiftUI
import AnalyzersKit

/// A run inside one engine log, found again by its header line.
struct RunReference: Hashable, Codable {
    let log: EngineLog
    let header: String

    init(log: EngineLog, header: String) {
        self.log = log
        self.header = header
    }

    private enum CodingKeys: String, CodingKey { case log, header }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .log)
        guard let log = EngineLog(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .log, in: container,
                                                   debugDescription: "unknown log \(raw)")
        }
        self.log = log
        header = try container.decode(String.self, forKey: .header)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(log.rawValue, forKey: .log)
        try container.encode(header, forKey: .header)
    }
}

/// What can be pushed in the System group.
enum SystemRoute: Hashable, Codable {
    case run(RunReference)
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
        resolve: resolve)

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
        case .run(let run): RunDetailView(route: run)
        case .changes: LogsSettingsView(kind: .persistence)
        }
    }

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "network": Location(network)
        case "reports": Location(reports)
        case "loginitems", "log:loginItems": Location(loginItems)
        case "log:persistence": Location(loginItems, path: [.system(.changes)])
        default: nil
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
