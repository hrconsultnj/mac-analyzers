import SwiftUI

/// What can be pushed in the Memory group.
enum MemoryRoute: Hashable, Codable, Sendable {
    case dossier(DossierRoute)
    case forensics(ForensicsRoute)
    case forensicsList
    case reclaimLog
}

/// Monitor, Memory Guard and Memory Cleanup.
///
/// Interim: Memory Guard hosts the guard log (forensics pushed from it),
/// Memory Cleanup hosts the leftovers log with a way to the review screen.
@MainActor
enum MemoryGroup {

    static let monitor = SectionID("monitor")
    static let memoryGuard = SectionID("memoryGuard")
    static let memoryCleanup = SectionID("memoryCleanup")

    static let group = SidebarGroup(
        title: "Memory",
        rows: [
            SidebarRow(monitor, "Monitor", symbol: "gauge.with.dots.needle.67percent"),
            SidebarRow(memoryGuard, "Memory Guard", symbol: "shield.lefthalf.filled"),
            SidebarRow(memoryCleanup, "Memory Cleanup", symbol: "sparkles"),
        ],
        root: screen,
        resolve: resolve)

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case monitor: MonitorSettingsView()
        case memoryGuard: GuardRoot()
        case memoryCleanup: CleanupRoot()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: MemoryRoute) -> some View {
        switch route {
        case .dossier(let route): DossierView(route: route)
        case .forensics(let route): ForensicsDetailView(route: route)
        case .forensicsList: ForensicsBrowserView()
        case .reclaimLog: ReapLogView(kind: .reclaim)
        }
    }

    private static func resolve(_ target: String) -> Location? {
        switch target {
        case "monitor": Location(monitor)
        // "activity" keeps its old meaning: both callers want guard events
        case "activity", "log:guardLog": Location(memoryGuard)
        case "log:forensics": Location(memoryGuard, path: [.memory(.forensicsList)])
        case "log:memoryClean": Location(memoryCleanup)
        case "log:reclaim": Location(memoryCleanup, path: [.memory(.reclaimLog)])
        default: nil
        }
    }
}

private struct GuardRoot: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        GuardLogView()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Forensics") { navigator.push(.memory(.forensicsList)) }
                        .help("Every crisis report the guard wrote")
                }
            }
    }
}

private struct CleanupRoot: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ReapLogView(kind: .memoryClean)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Reclaim Log") { navigator.push(.memory(.reclaimLog)) }
                    Button("Review…") { navigator.open(target: "actions:memoryClean") }
                        .help("Preview what a cleanup would do, then apply it")
                }
            }
    }
}
