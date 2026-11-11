import AnalyzersKit
import SwiftUI

/// One category as an outline: an app or developer is a row that opens to its
/// items (a lone item is just a row), sortable by any column.
struct StartupItemTable: View {
    let groups: [StartupGroup]
    @Binding var selection: StartupNode.ID?
    /// Which groups the person opened or closed; a group nobody touched is open
    /// when the category has only a few, closed when it has many.
    @Binding var opened: [StartupGroup.ID: Bool]
    let onShowInFinder: (StartupItem) -> Void
    let onRemove: (StartupItem) -> Void

    /// The Administrator and Belongs To columns start hidden: the filter and the
    /// inspector say them. The column menu (right-click the header) brings them back.
    @State private var columns = TableColumnCustomization<StartupNode>()
    @State private var sortOrder: [KeyPathComparator<StartupNode>] = [
        KeyPathComparator(\.findingRank),
        KeyPathComparator(\.title, comparator: .localizedStandard),
    ]

    private var sortedGroups: [StartupGroup] {
        let nodes = groups.map(StartupNode.init(group:)).sorted(using: sortOrder)
        return nodes.compactMap { $0.group }
    }

    private func members(_ group: StartupGroup) -> [StartupNode] {
        group.items.map { StartupNode(item: $0, in: group, standalone: false) }.sorted(using: sortOrder)
    }

    var body: some View {
        Table(of: StartupNode.self, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columns) {
            TableColumn("Name", sortUsing: KeyPathComparator(\.title, comparator: .localizedStandard)) { node in
                StartupNodeName(node: node)
            }
            .width(min: 150, ideal: 220)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)
            // what the audit found comes right after the name: it is why a
            // person looks at this screen, so it stays on screen when an
            // inspector narrows the table
            TableColumn("Finding", sortUsing: KeyPathComparator(\.findingRank)) { node in
                let finding = node.item?.finding ?? node.group?.worstFinding ?? .fine
                Text(finding.title ?? "")
                    .foregroundStyle(color(finding).map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            }
            .width(min: 125, ideal: 130)
            .customizationID("finding")
            TableColumn("State", sortUsing: KeyPathComparator(\.stateText)) { node in
                Text(node.stateText).foregroundStyle(node.isGroup ? .secondary : .primary)
            }
            .width(min: 90, ideal: 130)
            .customizationID("state")
            TableColumn("Kind", sortUsing: KeyPathComparator(\.kindText)) { node in
                Text(node.kindText).foregroundStyle(node.isGroup ? .secondary : .primary)
            }
            .width(min: 95, ideal: 110)
            .customizationID("kind")
            TableColumn("Belongs To", sortUsing: KeyPathComparator(\.ownerText, comparator: .localizedStandard)) { node in
                Text(node.ownerText).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 170)
            .customizationID("owner")
            .defaultVisibility(.hidden)
            TableColumn("Administrator", sortUsing: KeyPathComparator(\.adminText)) { node in
                Text(node.adminText).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100)
            .customizationID("administrator")
            .defaultVisibility(.hidden)
        } rows: {
            ForEach(sortedGroups) { group in
                if group.count == 1, let item = group.items.first {
                    TableRow(StartupNode(item: item, in: group, standalone: true))
                } else {
                    DisclosureTableRow(StartupNode(group: group), isExpanded: Binding(
                        get: { opened[group.id] ?? (groups.count <= 6) },
                        set: { opened[group.id] = $0 })) {
                        ForEach(members(group)) { TableRow($0) }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: StartupNode.ID.self) { ids in
            if let item = item(ids) {
                Button("Show in Finder") { onShowInFinder(item) }
                    .disabled(item.revealPath == nil)
                if item.canRemove {
                    Divider()
                    Button(StartupRemoval.canNarrowToSelection ? "Remove Leftover…" : "Remove Leftovers…") {
                        onRemove(item)
                    }
                }
            }
        } primaryAction: { ids in
            if let item = item(ids) { onShowInFinder(item) }
        }
    }

    private func item(_ ids: Set<StartupNode.ID>) -> StartupItem? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return groups.lazy.flatMap(\.items).first { $0.id == id }
    }

    private func color(_ finding: StartupItem.Finding) -> Color? {
        switch finding {
        case .leftover: .red
        case .possibleLeftover: .orange
        default: nil
        }
    }
}

/// The Name cell: an item's icon and name, or a group's icon, name and count.
struct StartupNodeName: View {
    let node: StartupNode

    var body: some View {
        if let item = node.item {
            Label {
                Text(node.title)
            } icon: {
                StartupIcon(item: item)
            }
        } else if let group = node.group {
            GroupCell(name: group.name, countText: group.countText) {
                if let first = group.items.first { StartupIcon(item: first) }
            }
        }
    }
}
