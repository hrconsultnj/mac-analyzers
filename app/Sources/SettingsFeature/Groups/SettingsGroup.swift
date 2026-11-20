import SwiftUI
import AnalyzersKit

/// What can be pushed over the Settings hub: the preference screens. The
/// agent screens (`.agents`, `.onDeviceModels`, `.capabilities`) follow the
/// same rule as the four originals — pushed over the hub as `Route.settings`,
/// deep links landing with the Settings row still selected. Only Agents has
/// a hub row; Agents itself leads to the other two.
enum SettingsRoute: String, Hashable, Codable, Sendable, CaseIterable {
    case memory, storage, notifications, schedule
    case agents, onDeviceModels, capabilities
    case engineClaude, engineCodex

    var title: String {
        switch self {
        case .memory: Names.Screen.memorySettings
        case .storage: Names.Screen.storageSettings
        case .notifications: Names.Screen.notifications
        case .schedule: Names.Screen.schedule
        case .agents: Names.Screen.agents
        case .onDeviceModels: Names.Screen.onDeviceModels
        case .capabilities: Names.Screen.capabilities
        case .engineClaude: "Claude Code"
        case .engineCodex: "Codex"
        }
    }
}

/// One sidebar row, Settings: the hub with the app's own configuration (appearance, sidebar icons, open at login, updates)
/// and a row for each preference screen, which opens as a screen pushed over it. The `memory`, `storage`,
/// `notifications` and `schedule` deep links land on those screens, with the Settings row still selected —
/// as do the agent screens' own (`agents`, `agentsModels`, `agentsCapabilities`).
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
            "agents": detail(.agents),
            "agentsModels": detail(.onDeviceModels),
            "agentsCapabilities": detail(.capabilities),
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
        case .agents: AgentsScreen()
        case .onDeviceModels: OnDeviceModelsScreen()
        case .capabilities: CapabilitiesScreen()
        case .engineClaude: EngineDetailScreen(engine: .claude)
        case .engineCodex: EngineDetailScreen(engine: .codex)
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
