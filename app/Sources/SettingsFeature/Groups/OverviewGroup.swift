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
/// Interim: Activity hosts the Logs landing, whose rows call the navigator.
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
        case activity: LogsHomeView()
        case setup: SetupSettingsView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: OverviewRoute) -> some View {
        switch route {
        case .turnOff: UninstallView()
        }
    }

    /// `job:<uuid>` lands on Activity. The pushed job screen (`Route.job`)
    /// arrives with the Activity screen; until then Activity's root is the
    /// closest honest place, and the link is never reported as unknown.
    private static func resolveDynamic(_ target: String) -> Resolution? {
        guard target.hasPrefix("job:"),
              UUID(uuidString: String(target.dropFirst("job:".count))) != nil
        else { return nil }
        return .main(Location(activity))
    }
}
