import SwiftUI
import AnalyzersKit

/// What can be pushed in the Storage group.
enum StorageRoute: Hashable, Codable, Sendable {
    /// The review-then-apply screen with one cleaner chosen (its raw value).
    case review(String)
}

/// Disk, Caches & Builds, Downloads, Temp & Agents and Spotlight. Time
/// Machine and Unused Apps arrive with their screens.
///
/// Interim: Caches & Builds IS the review screen for the storage cleaner;
/// Downloads and Temp & Agents reach theirs by pushing it from their own row.
@MainActor
enum StorageGroup {

    static let disk = SectionID("disk")
    static let caches = SectionID("caches")
    static let downloads = SectionID("downloads")
    static let temp = SectionID("temp")
    static let spotlight = SectionID("spotlight")

    private static let storageClean = ActionsSettingsView.Cleaner.storageClean.rawValue
    private static let janitor = ActionsSettingsView.Cleaner.janitor.rawValue
    private static let tempClean = ActionsSettingsView.Cleaner.tempClean.rawValue

    static let group = SidebarGroup(
        title: Names.Group.storage,
        rows: [
            SidebarRow(disk, Names.Screen.disk, symbol: "internaldrive"),
            SidebarRow(caches, Names.Screen.cachesAndBuilds, symbol: "shippingbox"),
            SidebarRow(downloads, Names.Screen.downloads, symbol: "arrow.down.circle"),
            SidebarRow(temp, Names.Screen.tempAndAgents, symbol: "tray.full"),
            SidebarRow(spotlight, Names.Screen.spotlight, symbol: "magnifyingglass"),
        ],
        root: screen,
        aliases: [
            "disk": .main(Location(disk)),
            // the storage-clean LOG is what StorageCleanView shows, and it is
            // hosted under Disk until Disk has its own screen
            "log:storageClean": .main(Location(disk)),
            "caches": .main(Location(caches)),
            "actions:storageClean": .main(Location(caches)),
            "downloads": .main(Location(downloads)),
            "log:janitor": .main(Location(downloads)),
            "actions:janitor": .main(Location(downloads, path: [.storage(.review(janitor))])),
            "temp": .main(Location(temp)),
            "log:tempSpace": .main(Location(temp)),
            "actions:tempClean": .main(Location(temp, path: [.storage(.review(tempClean))])),
            "spotlight": .main(Location(spotlight)),
            "log:spotlightAudit": .main(Location(spotlight)),
        ])

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case disk: StorageCleanView()
        case caches: ActionsSettingsView(preselect: .constant(storageClean))
        case downloads: DownloadsRoot()
        case temp: TempSpaceView()
        case spotlight: SpotlightAuditView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: StorageRoute) -> some View {
        switch route {
        case .review(let cleaner): ActionsSettingsView(preselect: .constant(cleaner))
        }
    }
}

private struct DownloadsRoot: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        StorageCleanView(kind: .janitor)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Review…") {
                        navigator.push(.storage(.review(ActionsSettingsView.Cleaner.janitor.rawValue)))
                    }
                    .help("Preview what the janitor would move to the Trash, then apply it")
                }
            }
    }
}
