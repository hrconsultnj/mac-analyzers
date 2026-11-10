import SwiftUI

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
            SidebarRow(setup, "Setup", symbol: "checklist.checked", badge: .needsAttention),
        ],
        root: screen,
        resolve: resolve)

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case overview: HomeSettingsView()
        case activity: LogsHomeView()
        case setup: SetupSettingsView()
        default: EmptyView()
        }
    }

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "home", "overview": Location(overview)
        case "logs", "jobs": Location(activity)
        case "setup": Location(setup)
        case "uninstall": Location(setup, path: [.app(.turnOff)])
        default: nil
        }
    }
}
