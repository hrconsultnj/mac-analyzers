import AnalyzersKit
import Foundation

/// One row of the outline: an app or developer (a parent that opens to its
/// items) or a single item. A `Table` holds one row type, so both are this.
struct StartupNode: Identifiable, Hashable {
    let item: StartupItem?
    let group: StartupGroup?
    /// What the Name column says: a group's name, or an item standing alone
    /// with its app in front, or an item inside its group.
    let title: String

    var id: String { item?.id ?? group?.id ?? title }

    init(group: StartupGroup) { self.group = group; item = nil; title = group.name }
    init(item: StartupItem, in group: StartupGroup, standalone: Bool) {
        self.item = item
        self.group = standalone ? group : nil
        title = standalone ? group.standaloneTitle(for: item) : item.name
    }

    var isGroup: Bool { item == nil }

    // sort keys: a KeyPathComparator needs plain Comparable properties
    var findingRank: Int { item?.finding.rank ?? group?.worstFinding.rank ?? 4 }
    var stateText: String { item?.stateTitle ?? group?.stateSummary ?? "" }
    var kindText: String { item?.kind.title ?? group?.countText ?? "" }
    var ownerText: String { item?.owner ?? group?.name ?? "" }
    var adminText: String { item.map { $0.needsAdministrator ? "Yes" : "No" } ?? "" }
}
