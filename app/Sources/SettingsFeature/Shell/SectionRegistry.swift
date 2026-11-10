import SwiftUI

/// The order of the sidebar groups, and lookups across them. This is the only
/// shared list: what a group contains lives in its own file.
@MainActor
enum SectionRegistry {

    static let groups: [SidebarGroup] = [
        OverviewGroup.group,
        MemoryGroup.group,
        StorageGroup.group,
        SystemGroup.group,
        HistoryGroup.group,
        PreferencesGroup.group,
        AppGroup.group,
    ]

    /// Opened when there is nothing to restore.
    static var home: Location { Location(OverviewGroup.overview) }

    static func contains(_ section: SectionID) -> Bool {
        groups.contains { $0.sections.contains(section) }
    }

    static func root(for section: SectionID) -> AnyView {
        groups.first { $0.sections.contains(section) }?.root(section)
            ?? OverviewGroup.group.root(OverviewGroup.overview)
    }

    static func row(for section: SectionID) -> SidebarRow? {
        groups.lazy.flatMap(\.rows).first { $0.section == section }
    }
}
