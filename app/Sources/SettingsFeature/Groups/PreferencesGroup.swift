import SwiftUI

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
        title: "Settings",
        rows: [
            SidebarRow(memory, "Memory", symbol: "memorychip"),
            SidebarRow(storage, "Storage", symbol: "internaldrive.fill"),
            SidebarRow(notifications, "Notifications", symbol: "bell.badge"),
            SidebarRow(schedule, "Schedule", symbol: "calendar.badge.clock"),
        ],
        root: screen,
        resolve: resolve)

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case memory: MemorySettingsView()
        case storage: StorageSettingsView()
        case notifications: NotifySettingsView()
        case schedule: ScheduleSettingsView()
        default: EmptyView()
        }
    }

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "memory": Location(memory)
        case "storage": Location(storage)
        case "notifications": Location(notifications)
        case "schedule": Location(schedule)
        default: nil
        }
    }
}
