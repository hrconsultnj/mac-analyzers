import SwiftUI
import AnalyzersKit

/// What can be pushed over the Settings hub: the four preference screens.
enum SettingsRoute: String, Hashable, Codable, Sendable, CaseIterable {
    case memory, storage, notifications, schedule

    var title: String {
        switch self {
        case .memory: Names.Screen.memorySettings
        case .storage: Names.Screen.storageSettings
        case .notifications: Names.Screen.notifications
        case .schedule: Names.Screen.schedule
        }
    }
}

/// One sidebar row, Settings: the hub with the app's own configuration (appearance, sidebar icons, open at login, updates)
/// and a row for each preference screen, which opens as a screen pushed over it. The `memory`, `storage`,
/// `notifications` and `schedule` deep links land on those screens, with the Settings row still selected.
@MainActor
enum SettingsGroup {

    static let settings = SectionID("settings")

    static let group = SidebarGroup(
        title: nil,
        rows: [
            SidebarRow(settings, Names.Screen.settings, symbol: "gearshape.fill", tint: .gray),
        ],
        root: screen,
        aliases: [
            "settings": .main(Location(settings)),
            "memory": detail(.memory),
            "storage": detail(.storage),
            "notifications": detail(.notifications),
            "schedule": detail(.schedule),
        ])

    private static func detail(_ route: SettingsRoute) -> Resolution {
        .main(Location(settings, path: [.settings(route)]))
    }

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case settings: SettingsHubView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .memory: MemorySettingsView()
        case .storage: StorageSettingsView()
        case .notifications: NotifySettingsView()
        case .schedule: ScheduleSettingsView()
        }
    }

    /// Where a preferences tab lands (`.preferences(tab:)`): its screen over the hub.
    static func interimLocation(forTab tab: String) -> Location {
        switch tab {
        case "storage": Location(settings, path: [.settings(.storage)])
        case "notifications": Location(settings, path: [.settings(.notifications)])
        case "schedule": Location(settings, path: [.settings(.schedule)])
        default: Location(settings, path: [.settings(.memory)])
        }
    }
}

/// The name What's New's grouping (`Screens/App/Update/WhatsNewGroups.swift`) still uses for this group's location lookup.
typealias PreferencesGroup = SettingsGroup
