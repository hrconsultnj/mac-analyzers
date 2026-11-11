import SwiftUI
import AnalyzersKit

/// What can be pushed in the Memory group.
enum MemoryRoute: Hashable, Codable, Sendable {
    case dossier(DossierRoute)
    /// One row of Memory Guard's history, by its id.
    case guardEntry(String)
}

/// Monitor, Memory Guard and Memory Cleanup.
///
/// Memory Guard shows the guard's history (an entry pushed from it); Memory Cleanup previews, reviews
/// and applies the two cleanups, and lists their past runs.
@MainActor
enum MemoryGroup {

    static let monitor = SectionID("monitor")
    static let memoryGuard = SectionID("memoryGuard")
    static let memoryCleanup = SectionID("memoryCleanup")

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
            // what used to be reached as "activity" when it meant guard events (the panel's event
            // rows, the Overview's guard tile); "activity" itself is the Activity screen
            "guard": .main(Location(memoryGuard)),
            "log:guardLog": .main(Location(memoryGuard)),
            "log:forensics": guardLink(.crisisReports),
            "log:memoryClean": cleanupLink(.leftovers),
            "log:reclaim": cleanupLink(.everythingNow),
            // bare "actions" is the old default cleaner
            "actions": cleanupLink(.leftovers),
            "actions:memoryClean": cleanupLink(.leftovers),
            "actions:reclaim": cleanupLink(.everythingNow),
        ],
        resolveDynamic: resolveDynamic,
        runResults: [.memoryClean: { row in AnyView(CleanupRunResults(row: row)) },
                     .reclaim: { row in AnyView(CleanupRunResults(row: row)) }])

    @ViewBuilder private static func screen(_ section: SectionID) -> some View {
        switch section {
        case monitor: MonitorView()
        case memoryGuard: GuardHistoryView()
        case memoryCleanup: MemoryCleanupView()
        default: EmptyView()
        }
    }

    @ViewBuilder static func destination(for route: MemoryRoute) -> some View {
        switch route {
        case .dossier(let route): DossierView(route: route)
        case .guardEntry(let id): GuardEntryScreen(id: id)
        }
    }

    private static func guardLink(_ scope: GuardHistory.Scope) -> Resolution {
        .mainWithIntent(Location(memoryGuard),
                        SectionIntent(section: memoryGuard, payload: GuardLink(scope: scope).payload))
    }

    private static func cleanupLink(_ scope: MemoryCleanupModel.Scope) -> Resolution {
        .mainWithIntent(Location(memoryCleanup),
                        SectionIntent(section: memoryCleanup, payload: CleanupLink(scope: scope).payload))
    }

    /// An `actions:` target naming no cleaner we know lands on the old
    /// default, as it always did. Exact targets for the other cleaners are
    /// answered first, by the groups that own them.
    private static func resolveDynamic(_ target: String) -> Resolution? {
        if target.hasPrefix("guard:"), let link = GuardLink.parse(String(target.dropFirst("guard:".count))) {
            return .mainWithIntent(Location(memoryGuard), SectionIntent(section: memoryGuard, payload: link.payload))
        }
        if target.hasPrefix("monitor:"), let link = MonitorLink.parse(String(target.dropFirst("monitor:".count))) {
            return .mainWithIntent(Location(monitor), SectionIntent(section: monitor, payload: link.payload))
        }
        return target.hasPrefix("actions:") ? cleanupLink(.leftovers) : nil
    }
}
