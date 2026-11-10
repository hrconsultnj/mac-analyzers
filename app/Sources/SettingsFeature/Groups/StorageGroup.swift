import SwiftUI

/// What can be pushed in the Storage group.
enum StorageRoute: Hashable, Codable, Sendable {
    /// The interim Actions screen with one cleaner chosen (its raw value).
    case cleaner(String)
}

/// Disk, Caches & Builds, Downloads, Temp & Agents, Spotlight — plus the
/// interim Actions row that hosts the review-then-apply screen until each
/// task has its own. Time Machine and Unused Apps arrive with their screens.
@MainActor
enum StorageGroup {

    static let disk = SectionID("disk")
    static let caches = SectionID("caches")
    static let downloads = SectionID("downloads")
    static let temp = SectionID("temp")
    static let spotlight = SectionID("spotlight")
    static let actions = SectionID("actions")

    static let group = SidebarGroup(
        title: "Storage",
        rows: [
            SidebarRow(disk, "Disk", symbol: "internaldrive"),
            SidebarRow(caches, "Caches & Builds", symbol: "shippingbox"),
            SidebarRow(downloads, "Downloads", symbol: "arrow.down.circle"),
            SidebarRow(temp, "Temp & Agents", symbol: "tray.full"),
            SidebarRow(spotlight, "Spotlight", symbol: "magnifyingglass"),
            SidebarRow(actions, "Actions", symbol: "checklist"),
        ],
        root: screen,
        resolve: resolve)

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case disk: StorageCleanView()
        case caches: ActionsSettingsView(preselect: .constant(ActionsSettingsView.Cleaner.storageClean.rawValue))
        case downloads: StorageCleanView(kind: .janitor)
        case temp: TempSpaceView()
        case spotlight: SpotlightAuditView()
        case actions: ActionsSettingsView(preselect: .constant(nil))
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: StorageRoute) -> some View {
        switch route {
        case .cleaner(let raw): ActionsSettingsView(preselect: .constant(raw))
        }
    }

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "disk": return Location(disk)
        case "caches", "log:storageClean": return Location(caches)
        case "downloads", "log:janitor": return Location(downloads)
        case "temp", "log:tempSpace": return Location(temp)
        case "spotlight", "log:spotlightAudit": return Location(spotlight)
        case "actions": return Location(actions)
        default:
            // "actions:<cleaner>" — the cleaner rides in the location, so a
            // link to the screen you are already on still switches it
            guard target.hasPrefix("actions:") else { return nil }
            let raw = String(target.dropFirst("actions:".count))
            guard ActionsSettingsView.Cleaner(rawValue: raw) != nil else { return Location(actions) }
            return Location(actions, path: [.storage(.cleaner(raw))])
        }
    }
}
