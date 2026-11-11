import SwiftUI
import Observation
import AnalyzersKit

/// What can be pushed from Overview, Activity and Setup.
enum OverviewRoute: Hashable, Codable {
    /// Turn Off or Remove, pushed from Setup.
    case turnOff
    /// The newest run of one log (an `EngineLog` raw value), looked up by the screen when it appears.
    case newestRun(String)
}

/// Whether anything on this Mac is not working, for the Setup row's badge.
@MainActor @Observable
final class SetupBadge {
    static let shared = SetupBadge()
    private(set) var needsAttention = false

    func refresh() async {
        // cheap version of the checklist: is anything actually broken?
        let engine = await Task.detached(priority: .utility) { EngineStatus.probe() }.value
        needsAttention = !engine.isFullyInstalled
    }
}

/// The three rows above the groups: where things stand (Overview), what has
/// run (Activity), and whether the app is set up (Setup).
///
/// Activity hosts `ActivityView`: every run, whoever started it, with a pushed
/// screen per job (`Route.job`).
@MainActor
enum OverviewGroup {

    static let overview = SectionID("overview")
    static let activity = SectionID("activity")
    static let setup = SectionID("setup")

    static let group = SidebarGroup(
        title: nil,
        rows: [
            SidebarRow(overview, Names.Screen.overview, symbol: "gauge.with.dots.needle.33percent"),
            SidebarRow(activity, Names.Screen.activity, symbol: "list.bullet.rectangle"),
            // The row STAYS after everything is green — permissions get
            // withdrawn and background jobs get unloaded without asking.
            // Only the badge goes away.
            SidebarRow(setup, Names.Screen.setup, symbol: "checklist.checked",
                       badge: { SetupBadge.shared.needsAttention ? "!" : nil }),
        ],
        root: screen,
        aliases: [
            "home": .main(Location(overview)),
            "overview": .main(Location(overview)),
            "logs": .main(Location(activity)),
            "jobs": .main(Location(activity)),
            "setup": .main(Location(setup)),
            "uninstall": .main(Location(setup, path: [.overview(.turnOff)])),
        ],
        resolveDynamic: resolveDynamic,
        load: { await SetupBadge.shared.refresh() })

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case overview: HomeSettingsView()
        case activity: ActivityView()
        case setup: SetupSettingsView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: OverviewRoute) -> some View {
        switch route {
        case .turnOff: UninstallView()
        case .newestRun(let raw): RunScreen(newestIn: EngineLog(rawValue: raw))
        }
    }

    /// Targets that carry data, all landing in Activity:
    ///  - `job:<uuid>` — that job's screen pushed (an id nobody recorded shows "no longer recorded");
    ///  - `activity:all|running|review|failed` — Activity with that scope chosen;
    ///  - `activity:run:<log>` — the newest run in that log (`storageClean`, `guardLog`, …) pushed;
    ///  - `activity:collapsed` — Activity with every day folded away;
    ///  - `activity:find:<text>` — Activity with that search typed in.
    /// Pure: the answer is the Activity root plus a one-shot request, or a pushed route. Nothing is
    /// read and no shared state is written here (the router resolves a link twice),
    /// and the screen applies or looks up what was asked when it appears.
    private static func resolveDynamic(_ target: String) -> Resolution? {
        if target.hasPrefix("job:") {
            guard let id = UUID(uuidString: String(target.dropFirst("job:".count))) else { return nil }
            return .main(Location(activity, path: [.job(id)]))
        }
        guard target.hasPrefix("activity:") else { return nil }
        let rest = String(target.dropFirst("activity:".count))
        if rest.hasPrefix("run:") {
            guard let log = EngineLog(rawValue: String(rest.dropFirst("run:".count))) else { return nil }
            return .main(Location(activity, path: [.overview(.newestRun(log.rawValue))]))
        }
        if rest == "collapsed" { return link(ActivityLink(collapsed: true)) }
        if rest.hasPrefix("find:") { return link(ActivityLink(query: String(rest.dropFirst("find:".count)))) }
        let scopes: [String: ActivityScope] = ["all": .all, "running": .running, "review": .needsReview,
                                               "failed": .failed]
        return scopes[rest].map { link(ActivityLink(scope: $0)) }
    }

    private static func link(_ link: ActivityLink) -> Resolution {
        .mainWithIntent(Location(activity), SectionIntent(section: activity, payload: link.payload))
    }
}
