import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// One row of the outline: an app or developer (a parent that opens to its items)
/// or a single item. An owner with ONE item is that item as a plain row, not a
/// group of one: this model decides it, the table only draws what it is given.
struct StartupNode: Identifiable, Hashable {
    let item: StartupItem?
    let group: StartupGroup?
    /// What the Name column says: a group's name, an item standing alone with its
    /// app in front, or an item inside its group.
    let title: String
    /// The items of a group of two or more; nil for an item (and for a lone one).
    let children: [StartupNode]?

    var id: String { item?.id ?? group?.id ?? title }

    var isGroup: Bool { item == nil }

    init(group: StartupGroup, sort: [KeyPathComparator<StartupNode>]) {
        self.group = group
        item = nil
        title = group.name
        children = group.items
            .map { StartupNode(item: $0, in: group, standalone: false) }
            .sorted(using: sort)
    }

    init(item: StartupItem, in group: StartupGroup, standalone: Bool) {
        self.item = item
        self.group = standalone ? group : nil
        title = standalone ? group.standaloneTitle(for: item) : item.name
        children = nil
    }

    /// The rows of a category, sorted at both levels; a group of one is its item.
    static func tree(_ groups: [StartupGroup], sort: [KeyPathComparator<StartupNode>]) -> [StartupNode] {
        groups.map { group in
            group.count == 1 && group.items.first != nil
                ? StartupNode(item: group.items[0], in: group, standalone: true)
                : StartupNode(group: group, sort: sort)
        }
        .sorted(using: sort)
    }

    // sort keys and the words of each cell: a KeyPathComparator needs plain Comparable properties
    var findingRank: Int { item?.finding.rank ?? group?.worstFinding.rank ?? 4 }
    var findingText: String { (item?.finding ?? group?.worstFinding ?? .fine).title ?? "" }
    var stateText: String { item?.stateTitle ?? group?.stateSummary ?? "" }
    var kindText: String { item?.kind.title ?? "" }
    var ownerText: String { item?.owner ?? group?.name ?? "" }
    var adminText: String { item.map { $0.needsAdministrator ? "Yes" : "No" } ?? "" }

    /// The icon of an item, or of a group's first item (the group cell sizes it, a row draws it at 16).
    var iconImage: Image {
        let first = item ?? group?.items.first
        if let icon = first?.appIcon { return Image(nsImage: icon) }
        return Image(systemName: first?.symbol ?? "gearshape")
    }
}

/// The Name cell of an item row (a group row uses `OutlineGroupCell`).
struct StartupNodeName: View {
    let node: StartupNode

    var body: some View {
        if node.isGroup, let group = node.group {
            OutlineGroupCell(name: group.name, summary: group.countText, icon: node.iconImage)
        } else {
            // an icon is a picture of a fixed size, not a control: 16 points, as the group cell draws it
            Label { Text(node.title) } icon: { node.iconImage.resizable().scaledToFit().frame(width: 16, height: 16) }
        }
    }
}
