import SwiftUI
import AnalyzersKit

/// What can be pushed in the Memory group.
enum MemoryRoute: Hashable, Codable, Sendable {
    case dossier(DossierRoute)
    case forensics(ForensicsRoute)
    case forensicsList
    case reclaimLog
    /// The review-then-apply screen with one cleaner chosen (its raw value).
    case review(String)
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

    private static let memoryClean = ActionsSettingsView.Cleaner.memoryClean.rawValue
    private static let reclaim = ActionsSettingsView.Cleaner.reclaim.rawValue

    static let group = SidebarGroup(
        title: Names.Group.memory,
        rows: [
            SidebarRow(monitor, Names.Screen.monitor, symbol: "gauge.with.dots.needle.67percent"),
            SidebarRow(memoryGuard, Names.Screen.memoryGuard, symbol: "shield.lefthalf.filled"),
            SidebarRow(memoryCleanup, Names.Screen.memoryCleanup, symbol: "sparkles"),
        ],
        root: screen,
        aliases: [
            "monitor": .main(Location(monitor)),
            // "activity" keeps its old meaning: both callers want guard events
            "activity": .main(Location(memoryGuard)),
            "log:guardLog": .main(Location(memoryGuard)),
            "log:forensics": .main(Location(memoryGuard, path: [.memory(.forensicsList)])),
            "log:memoryClean": .main(Location(memoryCleanup)),
            "log:reclaim": .main(Location(memoryCleanup, path: [.memory(.reclaimLog)])),
            // bare "actions" is the old default cleaner
            "actions": review(memoryClean),
            "actions:memoryClean": review(memoryClean),
            "actions:reclaim": review(reclaim),
        ],
        resolveDynamic: resolveDynamic)

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
        case .review(let cleaner): ActionsSettingsView(preselect: .constant(cleaner))
        }
    }

    private static func review(_ cleaner: String) -> Resolution {
        .main(Location(memoryCleanup, path: [.memory(.review(cleaner))]))
    }

    /// An `actions:` target naming no cleaner we know lands on the old
    /// default, as it always did. Exact targets for the other cleaners are
    /// answered first, by the groups that own them.
    private static func resolveDynamic(_ target: String) -> Resolution? {
        target.hasPrefix("actions:") ? review(memoryClean) : nil
    }
}

private struct GuardRoot: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        GuardLogView()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(Names.crisisReports) { navigator.push(.memory(.forensicsList)) }
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
                    Button("Review…") {
                        navigator.push(.memory(.review(ActionsSettingsView.Cleaner.memoryClean.rawValue)))
                    }
                    .help("Preview what a cleanup would do, then apply it")
                }
            }
    }
}
