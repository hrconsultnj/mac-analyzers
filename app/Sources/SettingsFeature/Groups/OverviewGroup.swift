import SwiftUI
import Observation
import AnalyzersKit

/// What can be pushed from Overview, Activity and Setup.
enum OverviewRoute: Hashable, Codable {
    /// Turn Off or Remove, pushed from Setup.
    case turnOff
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
            SidebarRow(overview, "Overview", symbol: "gauge.with.dots.needle.33percent"),
            SidebarRow(activity, "Activity", symbol: "list.bullet.rectangle"),
            // The row STAYS after everything is green — permissions get
            // withdrawn and background jobs get unloaded without asking.
            // Only the badge goes away.
            SidebarRow(setup, "Setup", symbol: "checklist.checked",
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
        }
    }

    /// `job:<uuid>` lands on Activity with that job's screen pushed. The router
    /// cannot know which jobs exist (the store belongs to the app), so the job
    /// screen is the one that sends an id it cannot find back to Activity's root.
    private static func resolveDynamic(_ target: String) -> Resolution? {
        guard target.hasPrefix("job:"),
              let id = UUID(uuidString: String(target.dropFirst("job:".count)))
        else { return nil }
        return .main(Location(activity, path: [.job(id)]))
    }
}
