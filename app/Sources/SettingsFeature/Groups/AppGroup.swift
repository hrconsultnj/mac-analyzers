import SwiftUI
import Observation
import AnalyzersKit
#if canImport(ProKit)
import ProKit
#endif

/// What can be pushed from the app's own screens.
enum AppRoute: Hashable, Codable, Sendable {
    /// One feature of What's New on its own screen, by its id (the release's version and its position in it).
    case whatsNew(String)
    /// One How It Works topic.
    case topic(HowItWorksTopic)
    /// One release's features, by its version ("next" for the unreleased section, "latest" for the newest shipped one).
    case release(String)
}

/// Whether a newer release exists, for the Updates row's badge: read from the app's one
/// `UpdateState` (the main window hands it over), never fetched or compared here.
@MainActor @Observable
final class UpdateBadge {
    static let shared = UpdateBadge()
    weak var state: UpdateState?
    var updateAvailable: Bool { state?.isAvailable ?? false }
}

/// The Mac Analyzers screen and what it opens: Updates (with What's New under it), How It Works and Support.
/// None of them has a sidebar row: the item at the foot of the sidebar opens the app screen, which leads to the rest.
///
/// A supporter build has no Support row: its badge at the foot of the
/// sidebar is the way in, and the `support` target still lands on the
/// licence screen.
@MainActor
enum AppGroup {

    static let app = SectionID("app")
    static let updates = SectionID("updates")
    static let howItWorks = SectionID("howItWorks")
    static let support = SectionID("support")

    /// The sections the foot-of-sidebar item stands for: it shows as selected on any of them.
    static let sections: Set<SectionID> = [app, updates, howItWorks, support]

    static let group = SidebarGroup(
        title: Names.Group.app,
        rows: rows,
        hidden: [support],
        root: screen,
        aliases: [
            "app": .main(Location(app)),
            "update": .main(Location(updates)),
            "about": .main(Location(howItWorks)),
            "howItWorks": .main(Location(howItWorks)),
            "support": .main(Location(support)),
        ],
        resolveDynamic: { target in
            if let link = whatsNewLink(target) { return link }
            // `howItWorks:<topic>`: How It Works with that topic's screen on top
            if let topic = HowItWorksTopic.parse(target) { return .main(Location(howItWorks, path: [.app(.topic(topic))])) }
            // `howItWorks:memory|storage|system|yourData`: the screen on that tab (a link only selects and navigates)
            if target.hasPrefix("howItWorks:"), let tab = HowItWorksTab(rawValue: String(target.dropFirst("howItWorks:".count))) {
                ScopeTabMemory.select(tab.rawValue, in: "howItWorks")
                return .main(Location(howItWorks))
            }
            return nil
        },
        load: nil)

    /// What's New lives on Updates, under the channel picker. `updates:whatsNew` opens Updates scrolled to the list,
    /// `updates:whatsNew:latest` pushes the newest release's screen over it, and `updates:whatsNew:<version>` the first
    /// feature of that release over the release.
    private static func whatsNewLink(_ target: String) -> Resolution? {
        if target == "updates:whatsNew" {
            // a one-shot request the Updates screen takes when it shows (never a flag a resolve could leave behind)
            return .mainWithIntent(Location(updates), SectionIntent(section: updates, payload: "whatsNew"))
        }
        let prefix = "updates:whatsNew:"
        guard target.hasPrefix(prefix) else { return nil }
        let version = String(target.dropFirst(prefix.count))
        guard !version.isEmpty else { return nil }
        if version == "latest" { return .main(Location(updates, path: [.app(.release("latest"))])) }
        return .main(Location(updates, path: [.app(.release(version)), .app(.whatsNew("\(version)#0"))]))
    }

    private static var rows: [SidebarRow] {
        var rows = [
            SidebarRow(app, Names.app, symbol: "macwindow", tint: .pink, inSidebar: false),
            SidebarRow(updates, Names.Screen.updates, symbol: "arrow.down.circle", tint: .pink, inSidebar: false),
            SidebarRow(howItWorks, Names.Screen.howItWorks, symbol: "questionmark.circle", tint: .pink, inSidebar: false),
        ]
        #if !canImport(ProKit)
        rows.append(SidebarRow(support, Names.Screen.support, symbol: "heart", tint: .pink, inSidebar: false))
        #endif
        return rows
    }

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case app: AppHomeView()
        case updates: UpdateSettingsView()
        case howItWorks: HowItWorksView()
        case support:
            #if canImport(ProKit)
            ProLicenseScreen()
            #else
            SupportSettingsView()
            #endif
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: AppRoute) -> some View {
        switch route {
        case .whatsNew(let id): WhatsNewDetailScreen(id: id)
        case .topic(let topic): TopicScreen(topic: topic)
        case .release(let version): WhatsNewReleaseScreen(version: version)
        }
    }
}
