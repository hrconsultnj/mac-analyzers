import SwiftUI
import AnalyzersKit

/// What can be pushed in the Storage group.
enum StorageRoute: Hashable, Codable, Sendable {
    /// Every time one Storage task ran (its `JobKind` raw value).
    case history(String)
    /// Example screens for `SnapshotRunner` (see `StorageGroup.fixtureTargets`).
    case fixture(String)
}

/// Disk, Caches & Builds, Downloads, Temp & Agents and Spotlight. Time Machine and Unused
/// Apps arrive with their screens.
///
/// Each cleanup is one screen: Preview in the toolbar, the preview's rows as tabs and groups
/// in the shared review table, one Apply, History one tap away. A finished run's own screen
/// shows the same tabs and groups (`runResults`).
@MainActor
enum StorageGroup {

    static let disk = SectionID("disk")
    static let caches = SectionID("caches")
    static let downloads = SectionID("downloads")
    static let temp = SectionID("temp")
    static let spotlight = SectionID("spotlight")

    /// Links to the example screens. Only `SnapshotRunner` installs them
    /// (`DeepLinkRouter.installFixtures` adds these to its own).
    static var fixtureTargets: [String: Resolution] {
        ["caches:fixture": .main(Location(caches, path: [.storage(.fixture("caches"))])),
         "downloads:fixture": .main(Location(downloads, path: [.storage(.fixture("downloads"))])),
         "temp:fixture": .main(Location(temp, path: [.storage(.fixture("temp"))])),
         "disk:fixture": .main(Location(disk, path: [.storage(.fixture("disk"))]))]
    }

    private static func log(_ log: EngineLog) -> Route { .overview(.raw(.log(log.rawValue))) }

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
            "log:storageClean": .main(Location(caches, path: [log(.storageClean)])),
            "caches": .main(Location(caches)),
            "actions:storageClean": .main(Location(caches)),
            "downloads": .main(Location(downloads)),
            "log:janitor": .main(Location(downloads, path: [log(.janitor)])),
            "actions:janitor": .main(Location(downloads)),
            "temp": .main(Location(temp)),
            "log:tempSpace": .main(Location(temp, path: [log(.tempSpace)])),
            "actions:tempClean": .main(Location(temp)),
            "spotlight": .main(Location(spotlight)),
            "log:spotlightAudit": .main(Location(spotlight, path: [log(.spotlightAudit)])),
        ],
        // `<screen>:<tab>`: choose the tab, then go to the screen
        resolveDynamic: { target in
            let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let valid: Bool
            switch parts[0] {
            case "caches": valid = CacheCategory(rawValue: parts[1]) != nil
            case "downloads": valid = DownloadCategory(rawValue: parts[1]) != nil
            case "temp": valid = TempCategory(rawValue: parts[1]) != nil
            default: return nil
            }
            guard valid else { return nil }
            ScopeTabMemory.select(parts[1], in: parts[0])
            return .main(Location(SectionID(parts[0])))
        },
        runResults: [
            .storageClean: { row in
                AnyView(StorageResultsView<CacheCategory>(row: row, kind: .storageClean, screenKey: "caches") { block, results in
                    CacheReview.build(lines: block.lines, banner: block.banner, results: results).rows
                }.id(row.id))
            },
            .janitor: { row in
                AnyView(StorageResultsView<DownloadCategory>(row: row, kind: .janitor, screenKey: "downloads") { block, results in
                    DownloadReview.build(lines: block.lines, results: results).rows
                }.id(row.id))
            },
            .tempClean: { row in
                AnyView(StorageResultsView<TempCategory>(row: row, kind: .tempClean, screenKey: "temp") { block, results in
                    TempReview.build(from: TempCleanParser.parse(runHeader: block.banner, lines: block.lines), results: results).rows
                }.id(row.id))
            },
            .spotlight: { row in
                AnyView(StorageResultsView<SpotlightCategory>(row: row, kind: .spotlight, screenKey: "spotlight") { block, _ in
                    SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: block.banner, lines: block.lines),
                                          current: { _ in nil }).rows
                }.id(row.id))
            },
        ])

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case disk: DiskScreen()
        case caches: CachesScreen()
        case downloads: DownloadsScreen()
        case temp: TempScreen()
        case spotlight: SpotlightScreen()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: StorageRoute) -> some View {
        switch route {
        case .history(let kind): StorageHistoryScreen(kind: JobKind(rawValue: kind) ?? .storageClean)
        case .fixture(let name):
            switch name {
            case "downloads": DownloadsScreen(fixture: StorageFixtures.downloads())
            case "temp": TempScreen(fixture: StorageFixtures.temp())
            case "disk": DiskScreen(fixture: StorageFixtures.disk())
            default: CachesScreen(fixture: StorageFixtures.caches())
            }
        }
    }
}
