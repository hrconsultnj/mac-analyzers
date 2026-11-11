import AnalyzersKit
import SwiftUI
import UIComponents

/// One category as an outline: an app or developer is a row that opens to its
/// items (a lone item is just a row), sortable by any column. The table is the
/// shared `OutlineTable`; this file only says which columns and what each shows.
struct StartupItemTable: View {
    let groups: [StartupGroup]
    /// Names the saved column widths and hidden columns: one per tab.
    let autosave: String
    @Binding var selection: StartupNode.ID?
    /// Which groups are open, kept across window close and relaunch.
    let expansion: RememberedExpansion<String>
    let onShowInFinder: (StartupItem) -> Void
    let onRemove: (StartupItem) -> Void

    @State private var sortOrder: [KeyPathComparator<StartupNode>] = [
        KeyPathComparator(\StartupNode.findingRank),
        KeyPathComparator(\StartupNode.title, comparator: .localizedStandard),
    ]

    var body: some View {
        let nodes = StartupNode.tree(groups, sort: sortOrder)
        OutlineTable(nodes, children: \.children, selection: $selection, sortOrder: $sortOrder,
                     expanded: expansion.binding, autosave: autosave) {
            OutlineColumn("name", Names.Column.name,
                          sortUsing: KeyPathComparator(\StartupNode.title, comparator: .localizedStandard)) { node in
                StartupNodeName(node: node)
            }
            .width(min: 150, ideal: 220)
            // what the audit found comes right after the name: it is why a person looks at this
            // screen, so it stays on screen when an inspector narrows the table
            OutlineColumn("finding", Names.Column.finding, text: \.findingText,
                          sortUsing: KeyPathComparator(\StartupNode.findingRank))
                .textStyle { node in
                    switch node.item?.finding ?? node.group?.worstFinding ?? .fine {
                    case .leftover: .critical
                    case .possibleLeftover: .warning
                    default: .secondary
                    }
                }
                .width(min: 125, ideal: 130)
            OutlineColumn("state", Names.Column.state, text: \.stateText,
                          sortUsing: KeyPathComparator(\StartupNode.stateText))
                .textStyle { $0.isGroup ? .secondary : .primary }
                .width(min: 90, ideal: 130)
            OutlineColumn("kind", Names.Column.kind, text: \.kindText,
                          sortUsing: KeyPathComparator(\StartupNode.kindText))
                .width(min: 95, ideal: 110)
            OutlineColumn("owner", Names.Column.belongsTo, text: \.ownerText,
                          sortUsing: KeyPathComparator(\StartupNode.ownerText, comparator: .localizedStandard))
                .textStyle { _ in .secondary }
                .width(min: 100, ideal: 170)
                .defaultHidden()
            OutlineColumn("administrator", Names.Column.administrator, text: \.adminText,
                          sortUsing: KeyPathComparator(\StartupNode.adminText))
                .textStyle { _ in .secondary }
                .width(min: 90, ideal: 100)
                .defaultHidden()
        }
        .contextMenu({ ids in
            if let item = item(ids, in: nodes) {
                Button("Show in Finder") { onShowInFinder(item) }
                    .disabled(item.revealPath == nil)
                if item.canRemove {
                    Divider()
                    Button(StartupRemoval.canNarrowToSelection ? "Remove Leftover…" : "Remove Leftovers…") {
                        onRemove(item)
                    }
                }
            }
        }, primaryAction: { ids in
            if let item = item(ids, in: nodes) { onShowInFinder(item) }
        })
        .id(autosave)
    }

    private func item(_ ids: Set<StartupNode.ID>, in nodes: [StartupNode]) -> StartupItem? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return groups.lazy.flatMap(\.items).first { $0.id == id }
    }
}
