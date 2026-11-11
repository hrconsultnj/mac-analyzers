import SwiftUI

/// The order of the sidebar groups, and lookups across them. This is the only
/// shared list: what a group contains lives in its own file.
@MainActor
enum SectionRegistry {

    static let groups: [SidebarGroup] = {
        let groups = [
            OverviewGroup.group,
            MemoryGroup.group,
            StorageGroup.group,
            SystemGroup.group,
            HistoryGroup.group,
            PreferencesGroup.group,
            AppGroup.group,
        ]
        assertNoDuplicates(in: groups)
        return groups
    }()

    /// Opened when there is nothing to restore.
    static var home: Location { Location(OverviewGroup.overview) }

    static func contains(_ section: SectionID) -> Bool {
        groups.contains { $0.sections.contains(section) }
    }

    static func root(for section: SectionID) -> AnyView {
        groups.first { $0.sections.contains(section) }?.root(section)
            ?? OverviewGroup.group.root(OverviewGroup.overview)
    }

    /// Two groups claiming the same target or section is a mistake that would
    /// otherwise be settled silently by group order. Checked once, in debug
    /// builds, the first time the registry is used.
    private static func assertNoDuplicates(in groups: [SidebarGroup]) {
        #if DEBUG
        var targets = Set<String>()
        var sections = Set<SectionID>()
        for group in groups {
            for target in group.aliases.keys {
                assert(targets.insert(target).inserted,
                       "deep-link target \"\(target)\" is claimed by more than one group")
            }
            for section in group.sections {
                assert(sections.insert(section).inserted,
                       "section \"\(section.rawValue)\" is owned by more than one group")
            }
        }
        #endif
    }
}
