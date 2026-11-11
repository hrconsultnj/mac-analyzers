import SwiftUI
import AnalyzersKit

/// INTERIM: the four preference forms as sidebar rows. They move into a
/// Settings window (and this file goes away) when that window is built; until
/// then the `memory`, `storage`, `notifications` and `schedule` deep links
/// land here.
@MainActor
enum PreferencesGroup {

    static let memory = SectionID("prefsMemory")
    static let storage = SectionID("prefsStorage")
    static let notifications = SectionID("prefsNotifications")
    static let schedule = SectionID("prefsSchedule")

    static let group = SidebarGroup(
        title: Names.Group.settings,
        rows: [
            SidebarRow(memory, Names.Screen.memorySettings, symbol: "memorychip"),
            SidebarRow(storage, Names.Screen.storageSettings, symbol: "internaldrive.fill"),
            SidebarRow(notifications, Names.Screen.notifications, symbol: "bell.badge"),
            SidebarRow(schedule, Names.Screen.schedule, symbol: "calendar.badge.clock"),
        ],
        root: screen,
        aliases: [
            "memory": .main(Location(memory)),
            "storage": .main(Location(storage)),
            "notifications": .main(Location(notifications)),
            "schedule": .main(Location(schedule)),
        ])

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case memory: MemorySettingsView()
        case storage: StorageSettingsView()
        case notifications: NotifySettingsView()
        case schedule: ScheduleSettingsView()
        default: EmptyView()
        }
    }

    /// Where a preferences tab lands while there is no Settings window. The
    /// phase that builds the window changes the aliases above to
    /// `.preferences(tab:)` and nothing outside this file.
    static func interimLocation(forTab tab: String) -> Location {
        switch tab {
        case "storage": Location(storage)
        case "notifications": Location(notifications)
        case "schedule": Location(schedule)
        default: Location(memory)
        }
    }
}
